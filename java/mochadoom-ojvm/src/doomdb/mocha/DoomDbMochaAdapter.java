/*
 * Copyright (C) 2026 DoomDB contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */
package doomdb.mocha;

import data.Tables;
import defines.skill_t;
import doom.DoomMain;
import java.awt.GraphicsEnvironment;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Blob;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.CRC32;
import mochadoom.Engine;
import savegame.IDoomSaveGame;
import savegame.IDoomSaveGameHeader;
import savegame.VanillaDSG;
import savegame.VanillaDSGHeader;
import s.DummySFX;
import v.renderers.DoomScreen;
import w.InputStreamSugar;

/** Catch-all SQL entry points for the pinned Mocha Doom OJVM engine. */
public final class DoomDbMochaAdapter {
  public static final String ENGINE_REVISION =
      "c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93";
  public static final String IWAD_ARTIFACT = "freedoom1.wad";
  private static DoomMain<?, ?> engine;
  private static int controlTurnHeld;
  private static String lastAudioJson = "[]";

  private DoomDbMochaAdapter() {}

  public static String probeSafe() {
    try {
      // Resolve the engine root without invoking its desktop entry point.
      Class.forName("doom.DoomMain", false,
          DoomDbMochaAdapter.class.getClassLoader());
      Tables.InitTables();
      return "ok|revision=" + ENGINE_REVISION
          + "|headless=" + GraphicsEnvironment.isHeadless()
          + "|fineSine=" + Tables.finesine.length
          + "|fineTangent=" + Tables.finetangent.length;
    } catch (Throwable failure) {
      return failure("probe", failure);
    }
  }

  public static String iwadProbeSafe() {
    try {
      Connection connection =
          DriverManager.getConnection("jdbc:default:connection:");
      try (PreparedStatement statement = connection.prepareStatement(
             "select engine_revision,payload_sha256,payload_bytes "
                 + "from doom_engine_artifact where artifact_name=?")) {
        statement.setString(1, IWAD_ARTIFACT);
        try (ResultSet rows = statement.executeQuery()) {
        if (!rows.next()) {
          return "error|stage=iwad|type=missing|message=" + IWAD_ARTIFACT;
        }
        String revision = rows.getString(1);
        String expectedSha = rows.getString(2);
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        long length = 0;
        byte[] header = new byte[4];
        int headerLength = 0;
        try (InputStream input = rows.getBinaryStream(3)) {
          byte[] buffer = new byte[64 * 1024];
          for (int read; (read = input.read(buffer)) >= 0;) {
            if (read == 0) continue;
            int copy = Math.min(read, header.length - headerLength);
            if (copy > 0) {
              System.arraycopy(buffer, 0, header, headerLength, copy);
              headerLength += copy;
            }
            digest.update(buffer, 0, read);
            length += read;
          }
        }
        String actualSha = hex(digest.digest());
        boolean iwad = headerLength == 4 && header[0] == 'I'
            && header[1] == 'W' && header[2] == 'A' && header[3] == 'D';
        if (!ENGINE_REVISION.equals(revision)) {
          return "error|stage=iwad|type=revision|actual=" + clean(revision);
        }
        if (!expectedSha.equals(actualSha)) {
          return "error|stage=iwad|type=sha|actual=" + actualSha;
        }
        if (!iwad) {
          return "error|stage=iwad|type=header|message=not-IWAD";
        }
          return "ok|artifact=" + IWAD_ARTIFACT + "|bytes=" + length
              + "|sha256=" + actualSha;
        }
      }
    } catch (Throwable failure) {
      return failure("iwad", failure);
    }
  }

  /** Initialize one session-private headless engine from the database IWAD. */
  public static synchronized String initializeSafe() {
    try {
      if (engine != null) return engineStatus("already-initialized");
      InputStreamSugar.setInjectedResource(loadIwadBytes());
      engine = Engine.createHeadless(
          "-iwad", IWAD_ARTIFACT, "-nosound", "-nomusic", "-indexed",
          "-width", "320", "-height", "200");
      // The database adapter advances exactly one caller-owned tic at a time.
      // Disable Mocha Doom's wall-clock/network command accumulation before the
      // first Display(), otherwise a restored retained engine can overflow its
      // unused network ring while it waits for the next AutoREST request.
      engine.singletics = true;
      engine.InitNew(skill_t.sk_medium, 1, 1);
      controlTurnHeld = 0;
      DummySFX.clearEvents();
      lastAudioJson = "[]";
      engine.Display();
      return engineStatus("initialized");
    } catch (Throwable failure) {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("initialize", failure);
    }
  }

  /** Apply exactly one caller-supplied Doom ticcmd and render its frame. */
  public static synchronized String stepSafe(
      int forwardMove, int sideMove, int angleTurn, int buttons) {
    long started = System.nanoTime();
    try {
      if (engine == null) {
        String initialized = initializeSafe();
        if (!initialized.startsWith("ok|")) return initialized;
      }
      int buffer = (engine.gametic / engine.getTicdup())
          % engine.netcmds[engine.consoleplayer].length;
      doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
      command.forwardmove = (byte) clamp(forwardMove, -127, 127);
      command.sidemove = (byte) clamp(sideMove, -127, 127);
      command.angleturn = (short) clamp(
          angleTurn, Short.MIN_VALUE, Short.MAX_VALUE);
      command.buttons = (char) (buttons & 0xff);
      command.chatchar = 0;
      command.lookfly = 0;
      command.consistancy = 0;
      long stageStarted = System.nanoTime();
      DummySFX.beginTic(engine.gametic + 1L);
      engine.Ticker();
      engine.gametic++;
      lastAudioJson = DummySFX.drainEvents(engine.gametic);
      long tickerMicros = (System.nanoTime() - stageStarted) / 1000L;
      stageStarted = System.nanoTime();
      engine.Display();
      long renderMicros = (System.nanoTime() - stageStarted) / 1000L;
      stageStarted = System.nanoTime();
      String status = engineStatus("stepped");
      long statusMicros = (System.nanoTime() - stageStarted) / 1000L;
      return status + "|tickerMicros=" + tickerMicros
          + "|renderMicros=" + renderMicros
          + "|statusMicros=" + statusMicros + "|elapsedMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("step", failure);
    }
  }

  /**
   * Map public normalized controls with vanilla keyboard semantics, apply one
   * tic, render it, and expose the exact durable 8-byte ticcmd in status.
   */
  public static synchronized String stepControlsFrameSafe(
      int turn, int forward, int strafe, int run, int fire, int use,
      int weapon, int pause, int automap, int menu, Blob output) {
    return stepControlsFrameInternal(turn, forward, strafe, run, fire, use,
        weapon, pause, automap, menu, output, true);
  }

  private static String stepControlsFrameInternal(
      int turn, int forward, int strafe, int run, int fire, int use,
      int weapon, int pause, int automap, int menu, Blob output,
      boolean writeRawFrame) {
    long started = System.nanoTime();
    try {
      if (engine == null) {
        String initialized = initializeSafe();
        if (!initialized.startsWith("ok|")) return initialized;
      }
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      turn = clamp(turn, -1, 1);
      forward = clamp(forward, -1, 1);
      strafe = clamp(strafe, -1, 1);
      run = clamp(run, 0, 1);
      fire = clamp(fire, 0, 1);
      use = clamp(use, 0, 1);
      weapon = clamp(weapon, 0, 9);
      pause = clamp(pause, 0, 1);
      automap = clamp(automap, 0, 1);
      menu = clamp(menu, 0, 1);

      if (turn == 0) {
        controlTurnHeld = 0;
      } else {
        controlTurnHeld += engine.getTicdup();
      }
      int turnMagnitude = controlTurnHeld < 6 ? 320
          : (run == 1 ? 1280 : 640);
      int buttons = (fire == 1 ? data.Defines.BT_ATTACK : 0)
          | (use == 1 ? data.Defines.BT_USE : 0);
      if (weapon > 0) {
        buttons |= data.Defines.BT_CHANGE
            | ((weapon - 1) << data.Defines.BT_WEAPONSHIFT);
      }
      if (pause == 1) {
        buttons = data.Defines.BT_SPECIAL | data.Defines.BTS_PAUSE;
      }
      int presentationFlags = (automap << 1) | (menu << 2);

      int buffer = (engine.gametic / engine.getTicdup())
          % engine.netcmds[engine.consoleplayer].length;
      doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
      command.forwardmove = (byte) (forward * (run == 1 ? 50 : 25));
      command.sidemove = (byte) (strafe * (run == 1 ? 40 : 24));
      // Public +1 is turn-right; vanilla represents right as a negative delta.
      command.angleturn = (short) (-turn * turnMagnitude);
      // Single-player consistency is otherwise unused. Persist presentation
      // toggles here so the canonical eight-byte ticcmd ledger reconstructs
      // automap/menu state across save/load and worker restarts.
      command.consistancy = (short) presentationFlags;
      command.chatchar = 0;
      command.buttons = (char) (buttons & 0xff);
      command.lookfly = 0;
      byte[] packedCommand = Arrays.copyOf(
          command.pack(), doom.ticcmd_t.TICCMDLEN);

      long stageStarted = System.nanoTime();
      applyPresentationFlags(presentationFlags);
      DummySFX.beginTic(engine.gametic + 1L);
      engine.Ticker();
      engine.gametic++;
      lastAudioJson = DummySFX.drainEvents(engine.gametic);
      long tickerMicros = (System.nanoTime() - stageStarted) / 1000L;
      stageStarted = System.nanoTime();
      engine.Display();
      long renderMicros = (System.nanoTime() - stageStarted) / 1000L;
      stageStarted = System.nanoTime();
      if (writeRawFrame) writeBlob(output, currentFrame());
      long blobMicros = (System.nanoTime() - stageStarted) / 1000L;
      return engineStatus("controls-stepped") + "|commandHex="
          + hex(packedCommand) + "|turnHeld=" + controlTurnHeld
          + "|audioJson=" + lastAudioJson
          + "|tickerMicros=" + tickerMicros + "|renderMicros="
          + renderMicros + "|blobMicros=" + blobMicros
          + "|elapsedMicros=" + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      controlTurnHeld = 0;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("step-controls-frame", failure);
    }
  }

  /** Apply normalized controls and return the existing gzip/DMF3 wire envelope. */
  public static synchronized String stepControlsPayloadSafe(
      int turn, int forward, int strafe, int run, int fire, int use,
      int weapon, int pause, int automap, int menu,
      String previousStateSha, Blob output) {
    long started = System.nanoTime();
    try {
      if (previousStateSha == null
          || !previousStateSha.matches("[0-9a-f]{64}")) {
        throw new IllegalArgumentException("previous state SHA required");
      }
      // The public payload call writes the final DMF3 envelope once. Writing a
      // raw 64 KB frame first only to truncate and overwrite the same locator
      // doubled the hottest OJVM-to-SecureFile boundary.
      String stepped = stepControlsFrameInternal(
          turn, forward, strafe, run, fire, use, weapon,
          pause, automap, menu, output, false);
      if (!stepped.startsWith("ok|")) return stepped;
      String commandHex = statusField(stepped, "commandHex");
      String frameSha = statusField(stepped, "frameSha256");
      String stateMaterial = previousStateSha + '|' + commandHex + '|'
          + frameSha + '|' + deterministicStateMaterial();
      String stateSha = hex(MessageDigest.getInstance("SHA-256").digest(
          stateMaterial.getBytes(StandardCharsets.US_ASCII)));
      long codecStarted = System.nanoTime();
      byte[] payload = encodeDmf3(stateSha, frameSha);
      long codecMicros = (System.nanoTime() - codecStarted) / 1000L;
      long blobStarted = System.nanoTime();
      writeBlob(output, payload);
      long payloadBlobMicros = (System.nanoTime() - blobStarted) / 1000L;
      // The worker persists this exact payload and validates the digest shape.
      // Hashing the in-memory array avoids rereading the SecureFile locator.
      String payloadSha = hex(MessageDigest.getInstance("SHA-256").digest(payload));
      return stepped + "|stateSha256=" + stateSha + "|payloadBytes="
          + payload.length + "|payloadSha256=" + payloadSha
          + "|codecMicros=" + codecMicros + "|payloadBlobMicros="
          + payloadBlobMicros + "|payloadElapsedMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      controlTurnHeld = 0;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("step-controls-payload", failure);
    }
  }

  /** Encode the already-rendered retained frame without advancing a tic. */
  public static synchronized String currentPayloadSafe(
      String previousStateSha, Blob output) {
    long started = System.nanoTime();
    try {
      if (engine == null) throw new IllegalStateException("engine not initialized");
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      if (previousStateSha == null
          || !previousStateSha.matches("[0-9a-f]{64}")) {
        throw new IllegalArgumentException("previous state SHA required");
      }
      String frameSha = currentFrameSha();
      String stateSha = previousStateSha.matches("0{64}")
          ? hex(MessageDigest.getInstance("SHA-256").digest(
              ("INITIAL|" + frameSha + "|" + deterministicStateMaterial())
                  .getBytes(StandardCharsets.US_ASCII)))
          : previousStateSha;
      long codecStarted = System.nanoTime();
      byte[] payload = encodeDmf3(stateSha, frameSha);
      long codecMicros = (System.nanoTime() - codecStarted) / 1000L;
      long blobStarted = System.nanoTime();
      writeBlob(output, payload);
      long blobMicros = (System.nanoTime() - blobStarted) / 1000L;
      return engineStatus("current-payload") + "|stateSha256=" + stateSha
          + "|payloadBytes=" + payload.length + "|codecMicros=" + codecMicros
          + "|payloadBlobMicros=" + blobMicros + "|payloadElapsedMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      controlTurnHeld = 0;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("current-payload", failure);
    }
  }

  /** Start a caller-selected episode/map in the retained engine. */
  public static synchronized String newGameSafe(
      int skill, int episode, int map) {
    try {
      if (engine == null) {
        String initialized = initializeSafe();
        if (!initialized.startsWith("ok|")) return initialized;
      }
      skill_t[] skills = skill_t.values();
      engine.InitNew(skills[clamp(skill, 0, skills.length - 1)],
          clamp(episode, 1, 9), clamp(map, 1, 99));
      engine.singletics = true;
      controlTurnHeld = 0;
      DummySFX.clearEvents();
      lastAudioJson = "[]";
      engine.Display();
      return engineStatus("new-game");
    } catch (Throwable failure) {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("new-game", failure);
    }
  }

  /** Release all session-private retained engine and IWAD state. */
  public static synchronized String disposeSafe() {
    try {
      engine = null;
      controlTurnHeld = 0;
      lastAudioJson = "[]";
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return "ok|state=disposed";
    } catch (Throwable failure) {
      engine = null;
      controlTurnHeld = 0;
      lastAudioJson = "[]";
      return failure("dispose", failure);
    }
  }

  /** Copy the current indexed framebuffer into a caller-owned BLOB. */
  public static synchronized String frameSafe(Blob output) {
    long started = System.nanoTime();
    try {
      if (engine == null) throw new IllegalStateException("engine not initialized");
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      Object frame = engine.graphicSystem.getScreen(DoomScreen.FG);
      if (!(frame instanceof byte[])) {
        throw new IllegalStateException("indexed framebuffer unavailable");
      }
      byte[] pixels = (byte[]) frame;
      output.truncate(0);
      int first = Math.min(32767, pixels.length);
      int written = output.setBytes(1, pixels, 0, first);
      if (pixels.length > first) {
        written += output.setBytes(first + 1L, pixels, first,
            pixels.length - first);
      }
      if (written != pixels.length) {
        throw new IllegalStateException("short framebuffer BLOB write " + written);
      }
      return engineStatus("frame") + "|blobMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      return failure("frame", failure);
    }
  }

  /** Apply one dynamic command and hand its exact frame to the worker BLOB. */
  public static synchronized String stepFrameSafe(
      int forwardMove, int sideMove, int angleTurn, int buttons, Blob output) {
    try {
      String stepped = stepSafe(
          forwardMove, sideMove, angleTurn, buttons);
      if (!stepped.startsWith("ok|")) return stepped;
      String framed = frameSafe(output);
      if (!framed.startsWith("ok|")) return framed;
      return stepped + "|frameBlobBytes=" + output.length();
    } catch (Throwable failure) {
      return failure("step-frame", failure);
    }
  }

  /** Serialize the retained engine through Mocha Doom's native save codec. */
  public static synchronized String saveSafe(Blob output) {
    long started = System.nanoTime();
    try {
      if (engine == null) throw new IllegalStateException("engine not initialized");
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      IDoomSaveGameHeader header = new VanillaDSGHeader();
      header.setName("DoomDB checkpoint");
      header.setVersion("version " + data.Defines.VERSION);
      header.setGameskill(engine.gameskill);
      header.setGameepisode(engine.gameepisode);
      header.setGamemap(engine.gamemap);
      header.setPlayeringame(engine.playeringame);
      header.setLeveltime(engine.leveltime);
      IDoomSaveGame save = new VanillaDSG<Object, Object>(
          (DoomMain<Object, Object>) engine);
      save.setHeader(header);
      ByteArrayOutputStream bytes = new ByteArrayOutputStream(256 * 1024);
      boolean saved;
      try (DataOutputStream data = new DataOutputStream(bytes)) {
        saved = save.doSave(data);
      }
      if (!saved) throw new IllegalStateException("Mocha save codec failed");
      byte[] checkpoint = bytes.toByteArray();
      writeBlob(output, checkpoint);
      String sha = hex(MessageDigest.getInstance("SHA-256").digest(checkpoint));
      return engineStatus("saved") + "|checkpointBytes=" + checkpoint.length
          + "|checkpointSha256=" + sha + "|saveMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      return failure("save", failure);
    }
  }

  /** Reconstruct a retained engine from a verified database checkpoint BLOB. */
  public static synchronized String loadSafe(
      Blob input, String expectedSha, long expectedTic) {
    long started = System.nanoTime();
    try {
      if (engine == null) throw new IllegalStateException("engine not initialized");
      if (input == null) throw new IllegalArgumentException("input BLOB required");
      byte[] checkpoint = readBlob(input, 16L * 1024L * 1024L);
      String actualSha = hex(
          MessageDigest.getInstance("SHA-256").digest(checkpoint));
      if (expectedSha == null || !actualSha.equals(expectedSha)) {
        throw new IllegalArgumentException("checkpoint SHA mismatch " + actualSha);
      }
      if (expectedTic < 0 || expectedTic > Integer.MAX_VALUE) {
        throw new IllegalArgumentException("checkpoint tic " + expectedTic);
      }
      VanillaDSGHeader header = new VanillaDSGHeader();
      try (DataInputStream data = new DataInputStream(
          new ByteArrayInputStream(checkpoint))) {
        header.read(data);
      }
      if (!("version " + data.Defines.VERSION).equals(header.getVersion())) {
        throw new IllegalArgumentException("checkpoint version mismatch");
      }
      engine.gameskill = header.getGameskill();
      engine.gameepisode = header.getGameepisode();
      engine.gamemap = header.getGamemap();
      System.arraycopy(header.getPlayeringame(), 0, engine.playeringame, 0,
          engine.playeringame.length);
      engine.InitNew(engine.gameskill, engine.gameepisode, engine.gamemap);
      engine.singletics = true;
      engine.leveltime = header.getLeveltime();
      IDoomSaveGame save = new VanillaDSG<Object, Object>(
          (DoomMain<Object, Object>) engine);
      boolean loaded;
      try (DataInputStream data = new DataInputStream(
          new ByteArrayInputStream(checkpoint))) {
        loaded = save.doLoad(data);
      }
      if (!loaded) throw new IllegalStateException("Mocha load codec failed");
      engine.gametic = (int) expectedTic;
      engine.Display();
      return engineStatus("loaded") + "|checkpointBytes=" + checkpoint.length
          + "|checkpointSha256=" + actualSha + "|loadMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("load", failure);
    }
  }

  /** Rebuild exactly from new-game parameters and packed durable ticcmds. */
  public static synchronized String reconstructSafe(
      int skill, int episode, int map, Blob commandStream,
      String expectedFrameSha) {
    long started = System.nanoTime();
    try {
      if (commandStream == null) {
        throw new IllegalArgumentException("command stream required");
      }
      byte[] commands = readBlob(commandStream, 8L * 1024L * 1024L);
      if (commands.length % doom.ticcmd_t.TICCMDLEN != 0) {
        throw new IllegalArgumentException("command stream length "
            + commands.length);
      }
      disposeSafe();
      String initialized = initializeSafe();
      if (!initialized.startsWith("ok|")) return initialized;
      String newGame = newGameSafe(skill, episode, map);
      if (!newGame.startsWith("ok|")) return newGame;

      int commandCount = commands.length / doom.ticcmd_t.TICCMDLEN;
      controlTurnHeld = 0;
      for (int index = 0; index < commandCount; index++) {
        int offset = index * doom.ticcmd_t.TICCMDLEN;
        int buffer = (engine.gametic / engine.getTicdup())
            % engine.netcmds[engine.consoleplayer].length;
        doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
        // Upstream ticcmd_t.unpack sign-extends the low byte of both shorts
        // (for example FEC0 becomes FFC0). Decode the network-order ledger
        // explicitly so every possible 8-byte command replays byte-exactly.
        command.forwardmove = commands[offset];
        command.sidemove = commands[offset + 1];
        command.angleturn = (short) (((commands[offset + 2] & 0xff) << 8)
            | (commands[offset + 3] & 0xff));
        command.consistancy = (short) (((commands[offset + 4] & 0xff) << 8)
            | (commands[offset + 5] & 0xff));
        command.chatchar = (char) (commands[offset + 6] & 0xff);
        command.buttons = (char) (commands[offset + 7] & 0xff);
        command.lookfly = 0;
        controlTurnHeld = command.angleturn == 0
            ? 0 : controlTurnHeld + engine.getTicdup();
        applyPresentationFlags(command.consistancy & 0x06);
        DummySFX.beginTic(engine.gametic + 1L);
        engine.Ticker();
        engine.gametic++;
        lastAudioJson = DummySFX.drainEvents(engine.gametic);
        engine.Display();
      }
      String actualFrameSha = currentFrameSha();
      if (expectedFrameSha != null && !expectedFrameSha.isEmpty()
          && !actualFrameSha.equals(expectedFrameSha)) {
        throw new IllegalStateException("reconstruction frame mismatch actual="
            + actualFrameSha);
      }
      String commandSha = hex(
          MessageDigest.getInstance("SHA-256").digest(commands));
      return engineStatus("reconstructed") + "|replayedCommands="
          + commandCount + "|commandSha256=" + commandSha
          + "|reconstructMicros="
          + ((System.nanoTime() - started) / 1000L);
    } catch (Throwable failure) {
      engine = null;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return failure("reconstruct", failure);
    }
  }

  /** Run a bounded moving/firing route entirely inside the retained JVM. */
  public static synchronized String benchmarkSafe(
      int samples, int warmups, int forwardMove, int sideMove,
      int angleTurn, int fireEvery) {
    try {
      if (engine == null) throw new IllegalStateException("engine not initialized");
      samples = clamp(samples, 1, 2000);
      warmups = clamp(warmups, 0, 500);
      fireEvery = clamp(fireEvery, 0, 1024);
      long[] tickerMicros = new long[samples];
      long[] renderMicros = new long[samples];
      long[] totalMicros = new long[samples];
      Set<Long> frameCrcs = new HashSet<Long>();
      CRC32 crc = new CRC32();

      for (int index = -warmups; index < samples; index++) {
        long totalStarted = System.nanoTime();
        int buffer = (engine.gametic / engine.getTicdup())
            % engine.netcmds[engine.consoleplayer].length;
        doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
        command.forwardmove = (byte) clamp(forwardMove, -127, 127);
        command.sidemove = (byte) clamp(sideMove, -127, 127);
        command.angleturn = (short) clamp(
            angleTurn, Short.MIN_VALUE, Short.MAX_VALUE);
        command.buttons = (char) (fireEvery > 0
            && Math.floorMod(index + warmups, fireEvery) == 0 ? 1 : 0);
        command.chatchar = 0;
        command.lookfly = 0;
        long stageStarted = System.nanoTime();
        DummySFX.beginTic(engine.gametic + 1L);
        engine.Ticker();
        engine.gametic++;
        lastAudioJson = DummySFX.drainEvents(engine.gametic);
        long ticker = (System.nanoTime() - stageStarted) / 1000L;
        stageStarted = System.nanoTime();
        engine.Display();
        long render = (System.nanoTime() - stageStarted) / 1000L;
        if (index >= 0) {
          tickerMicros[index] = ticker;
          renderMicros[index] = render;
          totalMicros[index] = (System.nanoTime() - totalStarted) / 1000L;
          byte[] pixels = (byte[]) engine.graphicSystem.getScreen(DoomScreen.FG);
          crc.reset();
          crc.update(pixels, 0, pixels.length);
          frameCrcs.add(Long.valueOf(crc.getValue()));
        }
      }
      Arrays.sort(tickerMicros);
      Arrays.sort(renderMicros);
      Arrays.sort(totalMicros);
      return "ok|state=benchmarked|samples=" + samples + "|warmups=" + warmups
          + "|uniqueFrames=" + frameCrcs.size()
          + "|tickerP50Micros=" + percentile(tickerMicros, 50)
          + "|tickerP95Micros=" + percentile(tickerMicros, 95)
          + "|renderP50Micros=" + percentile(renderMicros, 50)
          + "|renderP95Micros=" + percentile(renderMicros, 95)
          + "|totalP50Micros=" + percentile(totalMicros, 50)
          + "|totalP95Micros=" + percentile(totalMicros, 95)
          + "|totalP99Micros=" + percentile(totalMicros, 99)
          + "|totalMaxMicros=" + totalMicros[totalMicros.length - 1];
    } catch (Throwable failure) {
      return failure("benchmark", failure);
    }
  }

  private static byte[] loadIwadBytes() throws Exception {
    Connection connection =
        DriverManager.getConnection("jdbc:default:connection:");
    try (PreparedStatement statement = connection.prepareStatement(
             "select engine_revision,payload_sha256,payload_bytes "
                 + "from doom_engine_artifact where artifact_name=?")) {
      statement.setString(1, IWAD_ARTIFACT);
      try (ResultSet rows = statement.executeQuery()) {
        if (!rows.next()) throw new IllegalStateException("IWAD missing");
        if (!ENGINE_REVISION.equals(rows.getString(1))) {
          throw new IllegalStateException("engine revision mismatch");
        }
        String expectedSha = rows.getString(2);
        Blob blob = rows.getBlob(3);
        long length = blob.length();
        if (length < 12 || length > Integer.MAX_VALUE) {
          throw new IllegalStateException("IWAD length " + length);
        }
        byte[] bytes = new byte[(int) length];
        int offset = 0;
        try (InputStream input = blob.getBinaryStream()) {
          while (offset < bytes.length) {
            int read = input.read(bytes, offset, bytes.length - offset);
            if (read < 0) throw new IllegalStateException("short IWAD read");
            if (read > 0) offset += read;
          }
        } finally {
          blob.free();
        }
        String actualSha = hex(
            MessageDigest.getInstance("SHA-256").digest(bytes));
        if (!expectedSha.equals(actualSha)) {
          throw new IllegalStateException("IWAD SHA mismatch " + actualSha);
        }
        return bytes;
      }
    }
  }

  private static byte[] readBlob(Blob blob, long maximumLength) throws Exception {
    long length = blob.length();
    if (length < 1 || length > maximumLength || length > Integer.MAX_VALUE) {
      throw new IllegalArgumentException("BLOB length " + length);
    }
    byte[] bytes = new byte[(int) length];
    int offset = 0;
    try (InputStream input = blob.getBinaryStream()) {
      while (offset < bytes.length) {
        int read = input.read(bytes, offset, bytes.length - offset);
        if (read < 0) throw new IllegalStateException("short BLOB read");
        if (read > 0) offset += read;
      }
    }
    return bytes;
  }

  private static void writeBlob(Blob output, byte[] bytes) throws Exception {
    output.truncate(0);
    int offset = 0;
    while (offset < bytes.length) {
      int count = Math.min(32767, bytes.length - offset);
      int written = output.setBytes(offset + 1L, bytes, offset, count);
      if (written != count) throw new IllegalStateException("short BLOB write");
      offset += count;
    }
  }

  private static String engineStatus(String state) throws Exception {
    Object frame = engine.graphicSystem.getScreen(DoomScreen.FG);
    if (!(frame instanceof byte[])) {
      throw new IllegalStateException("indexed framebuffer unavailable");
    }
    byte[] pixels = (byte[]) frame;
    String frameSha = currentFrameSha();
    doom.player_t player = engine.players[engine.consoleplayer];
    p.pspdef_t weaponSprite = player.psprites[0];
    p.pspdef_t flashSprite = player.psprites[1];
    String weaponState = weaponSprite.state == null ? "NONE"
        : Integer.toString(weaponSprite.state.id);
    String flashState = flashSprite.state == null ? "NONE"
        : Integer.toString(flashSprite.state.id);
    String playerState = player.mo == null ? "|player=missing"
        : "|playerX=" + player.mo.x + "|playerY=" + player.mo.y
            + "|playerZ=" + player.mo.z
            + "|playerAngle=" + Long.toUnsignedString(player.mo.angle)
            + "|playerHealth=" + player.health[0] + "|viewZ=" + player.viewz
            + "|damageCount=" + player.damagecount
            + "|attacker=" + (player.attacker == null
                ? "NONE" : player.attacker.type.name())
            + "|readyWeapon=" + player.readyweapon.name()
            + "|weaponState=" + weaponState
            + "|weaponTics=" + weaponSprite.tics
            + "|flashState=" + flashState
            + "|visibleSprites="
            + engine.sceneRenderer.getVisSpriteManager().getNumVisSprites();
    return "ok|state=" + state + "|tic=" + engine.gametic
        + "|levelTime=" + engine.leveltime
        + "|randomIndex=" + engine.random.getIndex()
        + "|paused=" + (engine.paused ? 1 : 0)
        + "|automap=" + (engine.automapactive ? 1 : 0)
        + "|menu=" + (engine.menuactive ? 1 : 0) + playerState
        + "|width=" + engine.graphicSystem.getScreenWidth()
        + "|height=" + engine.graphicSystem.getScreenHeight()
        + "|frameBytes=" + pixels.length + "|frameSha256=" + frameSha;
  }

  private static String currentFrameSha() throws Exception {
    return hex(MessageDigest.getInstance("SHA-256").digest(currentFrame()));
  }

  private static byte[] currentFrame() {
    Object frame = engine.graphicSystem.getScreen(DoomScreen.FG);
    if (!(frame instanceof byte[])) {
      throw new IllegalStateException("indexed framebuffer unavailable");
    }
    return (byte[]) frame;
  }

  private static String deterministicStateMaterial() {
    doom.player_t player = engine.players[engine.consoleplayer];
    String pose = player.mo == null ? "missing" : player.mo.x + ","
        + player.mo.y + "," + player.mo.z + ","
        + Long.toUnsignedString(player.mo.angle);
    return engine.gameskill.name() + '|' + engine.gameepisode + '|'
        + engine.gamemap + '|' + engine.gametic + '|' + engine.leveltime + '|'
        + engine.random.getIndex() + '|' + pose + '|' + player.health[0] + '|'
        + player.armorpoints + '|' + player.readyweapon.name() + '|'
        + player.pendingweapon.name() + '|' + player.viewz + '|' + lastAudioJson;
  }

  private static byte[] encodeDmf3(String stateSha, String frameSha)
      throws Exception {
    byte[] pixels = currentFrame();
    if (pixels.length != 320 * 200) {
      throw new IllegalStateException("DMF3 requires 320x200 indexed frame");
    }
    byte[] audio = lastAudioJson.getBytes(StandardCharsets.US_ASCII);
    if (audio.length > 65535) {
      throw new IllegalStateException("DMF3 audio payload too large");
    }
    byte[] payload = new byte[140 + audio.length + pixels.length];
    payload[0] = 'D'; payload[1] = 'M'; payload[2] = 'F'; payload[3] = '3';
    int tic = engine.gametic;
    payload[4] = (byte) (tic >>> 24);payload[5] = (byte) (tic >>> 16);
    payload[6] = (byte) (tic >>> 8);payload[7] = (byte) tic;
    doom.player_t player = engine.players[engine.consoleplayer];
    payload[8] = (byte) (player.health[0] <= 0 ? 1 : 0);
    byte[] stateBytes = stateSha.getBytes(StandardCharsets.US_ASCII);
    byte[] frameBytes = frameSha.getBytes(StandardCharsets.US_ASCII);
    System.arraycopy(stateBytes, 0, payload, 10, 64);
    System.arraycopy(frameBytes, 0, payload, 74, 64);
    payload[138] = (byte) (audio.length >>> 8);payload[139] = (byte) audio.length;
    System.arraycopy(audio, 0, payload, 140, audio.length);
    int offset = 140 + audio.length;
    // DMF3 preserves the legacy transport's column-major byte order. The
    // Mocha renderer is row-major, so transpose only at the public boundary.
    for (int x = 0; x < 320; x++) {
      for (int y = 0; y < 200; y++) payload[offset++] = pixels[y * 320 + x];
    }
    // ORDS already base64-encodes BLOBs. Returning the bounded binary envelope
    // directly avoids the measured OJVM gzip tail; clients retain legacy gzip
    // decoding and detect DMF3 before attempting decompression.
    return payload;
  }

  private static void applyPresentationFlags(int flags) {
    if ((flags & 0x02) != 0) {
      if (engine.automapactive) engine.autoMap.Stop();
      else engine.autoMap.Start();
    }
    if ((flags & 0x04) != 0) {
      if (engine.menuactive) engine.menu.ClearMenus();
      else engine.menu.StartControlPanel();
    }
  }

  private static String statusField(String status, String name) {
    String marker = "|" + name + "=";
    int start = status.indexOf(marker);
    if (start < 0) throw new IllegalArgumentException("missing status " + name);
    start += marker.length();
    int end = status.indexOf('|', start);
    return status.substring(start, end < 0 ? status.length() : end);
  }

  private static String failure(String stage, Throwable failure) {
    StringBuilder result = new StringBuilder("error|stage=").append(stage);
    Throwable current = failure;
    for (int depth = 0; current != null && depth < 4; depth++) {
      result.append("|type").append(depth).append('=')
          .append(clean(current.getClass().getName()))
          .append("|message").append(depth).append('=')
          .append(clean(current.getMessage()));
      StackTraceElement[] trace = current.getStackTrace();
      for (int index = 0; index < trace.length && index < 6; index++) {
        result.append("|at").append(depth).append('_').append(index)
            .append('=').append(clean(trace[index].toString()));
      }
      current = current.getCause();
    }
    return result.length() <= 3900
        ? result.toString() : result.substring(0, 3900);
  }

  private static String clean(String value) {
    if (value == null) return "";
    String cleaned = value.replace('|', '/').replace('\n', ' ')
        .replace('\r', ' ');
    return cleaned.length() <= 512 ? cleaned : cleaned.substring(0, 512);
  }

  private static int clamp(int value, int minimum, int maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private static long percentile(long[] sorted, int percentile) {
    int rank = (sorted.length * percentile + 99) / 100;
    return sorted[Math.max(0, Math.min(sorted.length - 1, rank - 1))];
  }

  private static String hex(byte[] bytes) {
    char[] alphabet = "0123456789abcdef".toCharArray();
    char[] result = new char[bytes.length * 2];
    for (int index = 0; index < bytes.length; index++) {
      int value = bytes[index] & 0xff;
      result[index * 2] = alphabet[value >>> 4];
      result[index * 2 + 1] = alphabet[value & 0xf];
    }
    return new String(result);
  }
}
