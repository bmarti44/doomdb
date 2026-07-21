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
import defines.ammotype_t;
import defines.skill_t;
import doom.DoomMain;
import doom.thinker_t;
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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.CRC32;
import mochadoom.Engine;
import p.mobj_t;
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
  private static short[][] multiplayerConsistency;
  private static byte[][] multiplayerPreviousTransport;
  private static byte[][] multiplayerTransportScratch;
  private static byte[][] multiplayerRawPayload;
  private static byte[][] multiplayerPackedPayload;
  private static int[] multiplayerPayloadLength;
  private static int multiplayerKeyframeInterval = 4;
  private static final int DEATHMATCH_FRAG_LIMIT = 10;
  private static final int DEATHMATCH_TIME_LIMIT_TICS = 10 * 60 * 35;
  private static final int MULTIPLAYER_PAYLOAD_CAPACITY = 128 * 1024;
  private static int deathmatchFragLimit;
  private static int deathmatchTimeLimitTics;

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
        weapon, pause, automap, menu, 0, output, true);
  }

  private static String stepControlsFrameInternal(
      int turn, int forward, int strafe, int run, int fire, int use,
      int weapon, int pause, int automap, int menu, int cheat, Blob output,
      boolean writeRawFrame) {
    long started = System.nanoTime();
    try {
      if (engine == null) {
        String initialized = initializeSafe();
        if (!initialized.startsWith("ok|")) return initialized;
      }
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      turn = clamp(turn, -127, 127);
      forward = clamp(forward, -127, 127);
      strafe = clamp(strafe, -127, 127);
      run = clamp(run, 0, 1);
      fire = clamp(fire, 0, 1);
      use = clamp(use, 0, 1);
      weapon = clamp(weapon, 0, 9);
      pause = clamp(pause, 0, 1);
      automap = clamp(automap, 0, 1);
      menu = clamp(menu, 0, 1);
      cheat = clamp(cheat, 0, 4);

      boolean mouseTurn = Math.abs(turn) > 1;
      if (turn == 0 || mouseTurn) {
        controlTurnHeld = 0;
      } else {
        controlTurnHeld += engine.getTicdup();
      }
      int turnMagnitude = mouseTurn ? Math.abs(turn) * 256
          : controlTurnHeld < 6 ? 320 : (run == 1 ? 1280 : 640);
      int buttons = (fire == 1 ? data.Defines.BT_ATTACK : 0)
          | (use == 1 ? data.Defines.BT_USE : 0);
      if (weapon > 0) {
        buttons |= data.Defines.BT_CHANGE
            | ((weapon - 1) << data.Defines.BT_WEAPONSHIFT);
      }
      if (pause == 1) {
        buttons = data.Defines.BT_SPECIAL | data.Defines.BTS_PAUSE;
      }
      int controlFlags = (automap << 1) | (menu << 2) | (cheat << 3);

      int buffer = (engine.gametic / engine.getTicdup())
          % engine.netcmds[engine.consoleplayer].length;
      doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
      command.forwardmove = (byte) (Math.abs(forward) > 1
          ? forward : forward * (run == 1 ? 50 : 25));
      command.sidemove = (byte) (Math.abs(strafe) > 1
          ? strafe : strafe * (run == 1 ? 40 : 24));
      // Public +1 is turn-right; vanilla represents right as a negative delta.
      command.angleturn = (short) (-Math.signum(turn) * turnMagnitude);
      // Single-player consistency is otherwise unused. Persist presentation
      // controls here so the canonical eight-byte ticcmd ledger reconstructs
      // automap, menu, and cheat state across save/load and worker restarts.
      command.consistancy = (short) controlFlags;
      command.chatchar = 0;
      command.buttons = (char) (buttons & 0xff);
      command.lookfly = 0;
      byte[] packedCommand = Arrays.copyOf(
          command.pack(), doom.ticcmd_t.TICCMDLEN);

      long stageStarted = System.nanoTime();
      applyControlFlags(controlFlags);
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
      int weapon, int pause, int automap, int menu, int cheat,
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
          pause, automap, menu, cheat, output, false);
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
      multiplayerConsistency = null;
      multiplayerPreviousTransport = null;
      multiplayerTransportScratch = null;
      multiplayerRawPayload = null;
      multiplayerPackedPayload = null;
      multiplayerPayloadLength = null;
      multiplayerKeyframeInterval = 4;
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
      return "ok|state=disposed";
    } catch (Throwable failure) {
      engine = null;
      controlTurnHeld = 0;
      lastAudioJson = "[]";
      multiplayerConsistency = null;
      multiplayerPreviousTransport = null;
      multiplayerTransportScratch = null;
      multiplayerRawPayload = null;
      multiplayerPackedPayload = null;
      multiplayerPayloadLength = null;
      multiplayerKeyframeInterval = 4;
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
        applyControlFlags(command.consistancy & 0x3e);
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

  /**
   * Disposable two-player feasibility proof for database-supplied ticcmd
   * vectors. This never shares the production retained engine: OJVM statics
   * are session-private and the probe always disposes its engine before return.
   */
  public static synchronized String multiplayerProbeSafe() {
    try {
      initializeMultiplayerProbe(2);
      if (!engine.netgame || engine.deathmatch
          || !engine.playeringame[0] || !engine.playeringame[1]) {
        throw new IllegalStateException("two-player membership not active");
      }
      if (engine.players[0].mo == null || engine.players[1].mo == null) {
        throw new IllegalStateException("two-player spawn missing");
      }
      int playerMobjs = activePlayerMobjCount();
      if (playerMobjs != 2) {
        throw new IllegalStateException("player mobj count " + playerMobjs);
      }

      // Face the authored E1M1 co-op starts toward one another. This makes the
      // two immutable POV renders exercise player-sprite projection rather
      // than merely producing different wall views.
      engine.players[0].mo.angle = data.Tables.ANG90;
      engine.players[1].mo.angle = data.Tables.ANG270;
      int beforeTic = engine.gametic;
      int beforeLevelTime = engine.leveltime;
      byte[] command0 = setMultiplayerCommand(0, 8, 0, 0, 0);
      byte[] command1 = setMultiplayerCommand(1, 0, -8, 256, 0);
      if (Arrays.equals(command0, command1)) {
        throw new IllegalStateException("ordered player commands collapsed");
      }
      tickMultiplayerEngine();
      int ticDelta = engine.gametic - beforeTic;
      int levelTimeDelta = engine.leveltime - beforeLevelTime;
      if (ticDelta != 1 || levelTimeDelta != 1) {
        throw new IllegalStateException("vector advanced world " + ticDelta
            + "/" + levelTimeDelta + " times");
      }
      if (!Arrays.equals(command0, engine.players[0].cmd.pack())
          || !Arrays.equals(command1, engine.players[1].cmd.pack())) {
        throw new IllegalStateException("executed command vector mismatch");
      }

      String beforeRender = multiplayerStateSha(2);
      int savedDisplay = engine.displayplayer;
      String frame0;
      String frame1;
      int visible0;
      int visible1;
      try {
        engine.displayplayer = 0;
        engine.Display();
        frame0 = currentFrameSha();
        visible0 = engine.sceneRenderer.getVisSpriteManager().getNumVisSprites();
        if (!beforeRender.equals(multiplayerStateSha(2))) {
          throw new IllegalStateException("player 0 render mutated world");
        }
        engine.displayplayer = 1;
        engine.Display();
        frame1 = currentFrameSha();
        visible1 = engine.sceneRenderer.getVisSpriteManager().getNumVisSprites();
        if (!beforeRender.equals(multiplayerStateSha(2))) {
          throw new IllegalStateException("player 1 render mutated world");
        }
      } finally {
        engine.displayplayer = savedDisplay;
      }
      if (frame0.equals(frame1)) {
        throw new IllegalStateException("two POV frames are identical");
      }
      if (visible0 < 1 || visible1 < 1) {
        throw new IllegalStateException("mutual sprite projection missing");
      }
      DummySFX.beginTic(engine.gametic + 1L);
      engine.doomSound.StartSound(engine.players[0].mo,
          data.sounds.sfxenum_t.sfx_pistol);
      String audio0 = DummySFX.drainEventsFor(engine.gametic + 1L,
          (s.AbstractDoomAudio) engine.doomSound, engine.players[0].mo);
      String audio1 = DummySFX.drainEventsFor(engine.gametic + 1L,
          (s.AbstractDoomAudio) engine.doomSound, engine.players[1].mo);
      boolean spatialAudio = !"[]".equals(audio0) && !"[]".equals(audio1)
          && !audio0.equals(audio1);
      if (!spatialAudio) {
        throw new IllegalStateException("per-listener spatial audio failed");
      }

      // Lock vanilla co-op pickup semantics in the shared world. Ordinary
      // ammo has one deterministic winner and is unlinked before another
      // player can contend for it; keys remain in netgames so every player can
      // acquire the same authored key independently.
      int clipIndex = ammotype_t.am_clip.ordinal();
      int ammo0Before = engine.players[0].ammo[clipIndex];
      int ammo1Before = engine.players[1].ammo[clipIndex];
      mobj_t clip = engine.actions.SpawnMobj(engine.players[0].mo.x,
          engine.players[0].mo.y, data.Defines.ONFLOORZ,
          data.mobjtype_t.MT_CLIP);
      engine.actions.TouchSpecialThing(clip, engine.players[0].mo);
      boolean pickupContention = engine.players[0].ammo[clipIndex] > ammo0Before
          && engine.players[1].ammo[clipIndex] == ammo1Before
          && clip.thinkerFunction == p.RemoveState.REMOVE;
      if (!pickupContention) {
        throw new IllegalStateException("co-op pickup contention failed");
      }
      mobj_t blueKey = engine.actions.SpawnMobj(engine.players[0].mo.x,
          engine.players[0].mo.y, data.Defines.ONFLOORZ,
          data.mobjtype_t.MT_MISC4);
      engine.actions.TouchSpecialThing(blueKey, engine.players[0].mo);
      engine.actions.TouchSpecialThing(blueKey, engine.players[1].mo);
      int blueCard = defines.card_t.it_bluecard.ordinal();
      boolean sharedKey = engine.players[0].cards[blueCard]
          && engine.players[1].cards[blueCard]
          && blueKey.thinkerFunction != p.RemoveState.REMOVE;
      if (!sharedKey) throw new IllegalStateException("co-op shared key failed");
      engine.actions.RemoveMobj(blueKey);

      // Both slots' action bits must survive one ordered vector and advance
      // the shared world only once. The route gate separately proves authored
      // door/lift/exit effects; this pins simultaneous fire/use ingestion.
      int actionBeforeTic = engine.gametic;
      setMultiplayerCommand(0, 0, 0, 0, data.Defines.BT_ATTACK);
      setMultiplayerCommand(1, 0, 0, 0, data.Defines.BT_USE);
      tickMultiplayerEngine();
      boolean simultaneousActions = engine.gametic == actionBeforeTic + 1
          && (engine.players[0].cmd.buttons & data.Defines.BT_ATTACK) != 0
          && (engine.players[1].cmd.buttons & data.Defines.BT_USE) != 0;
      if (!simultaneousActions) {
        throw new IllegalStateException("simultaneous player actions failed");
      }

      // Exercise shared combat ownership directly after the command/render
      // proof. DamageMobj is the same vanilla path used by hitscan/projectiles;
      // the source player must receive the frag and the victim must respawn in
      // the same authoritative engine.
      int fragBefore = engine.players[0].frags[1];
      engine.actions.DamageMobj(engine.players[1].mo, engine.players[0].mo,
          engine.players[0].mo, 10000);
      boolean dead = engine.players[1].health[0] == 0
          && engine.players[1].playerstate == data.Defines.PST_DEAD;
      int fragDelta = engine.players[0].frags[1] - fragBefore;
      if (!dead || fragDelta != 1) {
        throw new IllegalStateException("shared player damage/death failed");
      }
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, data.Defines.BT_USE);
      tickMultiplayerEngine();
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, 0);
      tickMultiplayerEngine();
      boolean reborn = engine.players[1].mo != null
          && engine.players[1].health[0] > 0
          && engine.players[1].playerstate == data.Defines.PST_LIVE;
      if (!reborn) throw new IllegalStateException("co-op reborn failed");

      return "ok|state=multiplayer-probed|membership=1100|netgame=1"
          + "|deathmatch=0|playerMobjs=" + playerMobjs + "|ticDelta=" + ticDelta
          + "|levelTimeDelta=" + levelTimeDelta
          + "|command0=" + hex(command0) + "|command1=" + hex(command1)
          + "|pov0Sha=" + frame0 + "|pov1Sha=" + frame1
          + "|pov0VisibleSprites=" + visible0
          + "|pov1VisibleSprites=" + visible1
          + "|renderStateSha=" + beforeRender
          + "|pickupWinner=0|sharedKey=1|simultaneousActions=1"
          + "|spatialAudio=1"
          + "|damage=10000|dead=1|fragDelta=" + fragDelta + "|reborn=1";
    } catch (Throwable failure) {
      return failure("multiplayer-probe", failure);
    } finally {
      disposeSafe();
    }
  }

  /** Disposable vanilla deathmatch spawn/score/reborn proof. */
  public static synchronized String deathmatchProbeSafe() {
    try {
      initializeMultiplayerEngine(2, 1, 3, 1, 1);
      if (!engine.netgame || !engine.deathmatch
          || engine.players[0].mo == null || engine.players[1].mo == null) {
        throw new IllegalStateException("deathmatch initialization failed");
      }
      int spawn0x = engine.players[0].mo.x;
      int spawn0y = engine.players[0].mo.y;
      int spawn1x = engine.players[1].mo.x;
      int spawn1y = engine.players[1].mo.y;
      if (spawn0x == spawn1x && spawn0y == spawn1y) {
        throw new IllegalStateException("deathmatch starts collapsed");
      }

      int fragBefore = engine.players[0].frags[1];
      mobj_t firstVictim = engine.players[1].mo;
      engine.actions.DamageMobj(firstVictim, engine.players[0].mo,
          engine.players[0].mo, 10000);
      if (engine.players[0].frags[1] != fragBefore + 1
          || engine.players[1].playerstate != data.Defines.PST_DEAD) {
        throw new IllegalStateException("deathmatch frag failed");
      }
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, data.Defines.BT_USE);
      tickMultiplayerEngine();
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, 0);
      tickMultiplayerEngine();
      boolean respawned = engine.players[1].playerstate == data.Defines.PST_LIVE
          && engine.players[1].mo != null && engine.players[1].mo != firstVictim
          && engine.players[1].health[0] > 0;
      if (!respawned) throw new IllegalStateException("deathmatch respawn failed");

      int p0TieBefore = engine.players[0].frags[1];
      int p1TieBefore = engine.players[1].frags[0];
      mobj_t p0 = engine.players[0].mo;
      mobj_t p1 = engine.players[1].mo;
      engine.actions.DamageMobj(p1, p0, p0, 10000);
      engine.actions.DamageMobj(p0, p1, p1, 10000);
      boolean simultaneousTie = engine.players[0].playerstate == data.Defines.PST_DEAD
          && engine.players[1].playerstate == data.Defines.PST_DEAD
          && engine.players[0].frags[1] == p0TieBefore + 1
          && engine.players[1].frags[0] == p1TieBefore + 1;
      if (!simultaneousTie) {
        throw new IllegalStateException("deathmatch simultaneous tie failed");
      }

      setMultiplayerCommand(0, 0, 0, 0, data.Defines.BT_USE);
      setMultiplayerCommand(1, 0, 0, 0, data.Defines.BT_USE);
      tickMultiplayerEngine();
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, 0);
      tickMultiplayerEngine();
      if (engine.players[0].playerstate != data.Defines.PST_LIVE
          || engine.players[1].playerstate != data.Defines.PST_LIVE) {
        throw new IllegalStateException("deathmatch dual respawn failed");
      }
      int suicideBefore = engine.players[0].frags[0];
      engine.actions.DamageMobj(engine.players[0].mo, engine.players[0].mo,
          engine.players[0].mo, 10000);
      int suicideDelta = engine.players[0].frags[0] - suicideBefore;
      if (suicideDelta != 1) {
        throw new IllegalStateException("deathmatch suicide attribution failed");
      }
      initializeMultiplayerEngine(2, 1, 3, 1, 1);
      deathmatchFragLimit = 1;
      engine.actions.DamageMobj(engine.players[1].mo, engine.players[0].mo,
          engine.players[0].mo, 10000);
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, 0);
      tickMultiplayerEngine();
      setMultiplayerCommand(0, 0, 0, 0, 0);
      setMultiplayerCommand(1, 0, 0, 0, 0);
      tickMultiplayerEngine();
      boolean limitIntermission =
          engine.gamestate == defines.gamestate_t.GS_INTERMISSION;
      if (!limitIntermission) {
        throw new IllegalStateException("deathmatch frag limit failed");
      }
      return "ok|state=deathmatch-probed|membership=1100|deathmatch=1"
          + "|spawn0=" + spawn0x + "," + spawn0y
          + "|spawn1=" + spawn1x + "," + spawn1y
          + "|frag=1|respawn=1|simultaneousTie=1|suicideDelta=" + suicideDelta
          + "|limitIntermission=1"
          + "|stateSha=" + multiplayerStateSha(2);
    } catch (Throwable failure) {
      return failure("deathmatch-probe", failure);
    } finally {
      disposeSafe();
    }
  }

  /** Benchmark one authoritative tic followed by one immutable POV per player. */
  public static synchronized String multiplayerBenchmarkSafe(
      int activePlayers, int samples, int warmups, Blob output) {
    try {
      activePlayers = clamp(activePlayers, 1, 4);
      samples = clamp(samples, 1, 2000);
      warmups = clamp(warmups, 0, 500);
      if (output == null) throw new IllegalArgumentException("output BLOB required");
      initializeMultiplayerProbe(activePlayers);
      long[] tickerMicros = new long[samples];
      long[][] renderMicros = new long[activePlayers][samples];
      long[][] codecMicros = new long[activePlayers][samples];
      long[][] blobMicros = new long[activePlayers][samples];
      long[] totalMicros = new long[samples];
      @SuppressWarnings("unchecked")
      Set<String>[] hashes = new Set[activePlayers];
      for (int player = 0; player < activePlayers; player++) {
        hashes[player] = new HashSet<String>();
      }

      for (int index = -warmups; index < samples; index++) {
        long totalStarted = System.nanoTime();
        for (int player = 0; player < activePlayers; player++) {
          setMultiplayerCommand(player, 0, 0,
              player % 2 == 0 ? 256 : -256, 0);
        }
        long stageStarted = System.nanoTime();
        tickMultiplayerEngine();
        long ticker = (System.nanoTime() - stageStarted) / 1000L;
        String stateBeforeRender = multiplayerStateSha(activePlayers);
        int savedDisplay = engine.displayplayer;
        try {
          for (int player = 0; player < activePlayers; player++) {
            engine.displayplayer = player;
            stageStarted = System.nanoTime();
            engine.Display();
            long render = (System.nanoTime() - stageStarted) / 1000L;
            stageStarted = System.nanoTime();
            byte[] frame = currentFrame();
            String frameSha = hex(
                MessageDigest.getInstance("SHA-256").digest(frame));
            long codec = (System.nanoTime() - stageStarted) / 1000L;
            stageStarted = System.nanoTime();
            writeBlob(output, frame);
            long blob = (System.nanoTime() - stageStarted) / 1000L;
            if (!stateBeforeRender.equals(multiplayerStateSha(activePlayers))) {
              throw new IllegalStateException("POV render mutated world player="
                  + player);
            }
            if (index >= 0) {
              renderMicros[player][index] = render;
              codecMicros[player][index] = codec;
              blobMicros[player][index] = blob;
              hashes[player].add(frameSha);
            }
          }
        } finally {
          engine.displayplayer = savedDisplay;
        }
        if (index >= 0) {
          tickerMicros[index] = ticker;
          totalMicros[index] = (System.nanoTime() - totalStarted) / 1000L;
        }
      }
      Arrays.sort(tickerMicros);
      Arrays.sort(totalMicros);
      StringBuilder result = new StringBuilder("ok|state=multiplayer-benchmarked")
          .append("|players=").append(activePlayers)
          .append("|samples=").append(samples)
          .append("|warmups=").append(warmups)
          .append("|tickerP50Micros=").append(percentile(tickerMicros, 50))
          .append("|tickerP95Micros=").append(percentile(tickerMicros, 95));
      for (int player = 0; player < activePlayers; player++) {
        Arrays.sort(renderMicros[player]);
        Arrays.sort(codecMicros[player]);
        Arrays.sort(blobMicros[player]);
        result.append("|pov").append(player).append("UniqueFrames=")
            .append(hashes[player].size())
            .append("|pov").append(player).append("RenderP50Micros=")
            .append(percentile(renderMicros[player], 50))
            .append("|pov").append(player).append("RenderP95Micros=")
            .append(percentile(renderMicros[player], 95))
            .append("|pov").append(player).append("CodecP95Micros=")
            .append(percentile(codecMicros[player], 95))
            .append("|pov").append(player).append("BlobP95Micros=")
            .append(percentile(blobMicros[player], 95));
      }
      return result.append("|totalP50Micros=")
          .append(percentile(totalMicros, 50))
          .append("|totalP95Micros=").append(percentile(totalMicros, 95))
          .append("|totalMaxMicros=").append(totalMicros[totalMicros.length - 1])
          .toString();
    } catch (Throwable failure) {
      return failure("multiplayer-benchmark", failure);
    } finally {
      disposeSafe();
    }
  }

  /**
   * Initialize one production retained multiplayer world and emit tic-zero
   * payloads into caller-owned locators. The returned state identity is shared
   * by every POV; frame and response identities remain player-specific.
   */
  public static synchronized String multiplayerNewGamePayloadsSafe(
      int activePlayers, int deathmatch, int skill, int episode, int map,
      Blob output0, Blob output1, Blob output2, Blob output3) {
    try {
      initializeMultiplayerEngine(
          activePlayers, deathmatch, skill, episode, map);
      String membership = multiplayerMembership(activePlayers);
      String stateSha = hashAscii("MULTI_INITIAL|" + membership + "|"
          + multiplayerStateSha(activePlayers));
      return renderMultiplayerPayloads(
          "multiplayer-new-game", activePlayers, membership, stateSha,
          new Blob[] {output0, output1, output2, output3});
    } catch (Throwable failure) {
      disposeSafe();
      return failure("multiplayer-new-game", failure);
    }
  }

  /**
   * Apply one canonical four-slot ticcmd vector, advance the shared world once,
   * then emit an immutable payload for each active POV. Inactive slots must be
   * all zero and client-supplied consistency words are ignored in favor of the
   * worker's retained consistency ring.
   */
  public static synchronized String multiplayerStepPayloadsSafe(
      int activePlayers, int membershipMask, String commandVectorHex,
      String previousStateSha,
      Blob output0, Blob output1, Blob output2, Blob output3) {
    try {
      requireMultiplayerEngine(activePlayers);
      applyMultiplayerMembership(activePlayers, membershipMask);
      if (previousStateSha == null
          || !previousStateSha.matches("[0-9a-f]{64}")) {
        throw new IllegalArgumentException("previous state SHA required");
      }
      byte[] requested = parseHex(commandVectorHex, 32);
      byte[] applied = new byte[32];
      for (int player = 0; player < 4; player++) {
        int offset = player * doom.ticcmd_t.TICCMDLEN;
        if (player >= activePlayers || !engine.playeringame[player]) {
          for (int index = 0; index < doom.ticcmd_t.TICCMDLEN; index++) {
            if (requested[offset + index] != 0) {
              throw new IllegalArgumentException(
                  "inactive player command " + player);
            }
          }
          continue;
        }
        int buffer = (engine.gametic / engine.getTicdup())
            % engine.netcmds[player].length;
        doom.ticcmd_t command = engine.netcmds[player][buffer];
        decodeMultiplayerCommand(command, requested, offset,
            multiplayerConsistency[player][buffer]);
        command.pack(applied, offset);
      }
      int beforeTic = engine.gametic;
      int beforeLevelTime = engine.leveltime;
      tickMultiplayerEngine();
      if (engine.gametic != beforeTic + 1
          || (engine.leveltime != beforeLevelTime + 1
              && engine.gamestate != defines.gamestate_t.GS_INTERMISSION)) {
        throw new IllegalStateException("multiplayer world did not advance once");
      }
      String membership = multiplayerMembership(activePlayers, membershipMask);
      String commandHex = hex(applied);
      String stateSha = hashAscii(previousStateSha + '|' + membership + '|'
          + commandHex + '|' + multiplayerStateSha(activePlayers));
      return renderMultiplayerPayloads(
          "multiplayer-step", activePlayers, membership, stateSha,
          new Blob[] {output0, output1, output2, output3})
          + "|commandVector=" + commandHex;
    } catch (Throwable failure) {
      disposeSafe();
      return failure("multiplayer-step", failure);
    }
  }

  /** Select the bounded transport keyframe cadence for this retained session. */
  public static synchronized String multiplayerKeyframeIntervalSafe(int interval) {
    try {
      if (engine == null || multiplayerConsistency == null) {
        throw new IllegalStateException("multiplayer engine not initialized");
      }
      if (interval != 4 && interval != 32) {
        throw new IllegalArgumentException("multiplayer keyframe interval");
      }
      multiplayerKeyframeInterval = interval;
      return "ok|keyframeInterval=" + interval;
    } catch (Throwable failure) {
      return failure("multiplayer-keyframes", failure);
    }
  }

  /** Rebuild a multiplayer world from its canonical ordered vector ledger. */
  public static synchronized String multiplayerReconstructPayloadsSafe(
      int activePlayers, int deathmatch, int skill, int episode, int map,
      Blob commandStream, String initialStateSha, String expectedStateSha,
      Blob output0, Blob output1, Blob output2, Blob output3) {
    try {
      if (commandStream == null || initialStateSha == null || expectedStateSha == null
          || !initialStateSha.matches("[0-9a-f]{64}")
          || !expectedStateSha.matches("[0-9a-f]{64}")) {
        throw new IllegalArgumentException("multiplayer reconstruction inputs");
      }
      // Tic-zero recovery has no command vectors yet. Keep readBlob's strict
      // non-empty contract for assets, saves, and frames while accepting the
      // one canonical empty stream here.
      byte[] vectors = commandStream.length() == 0L
          ? new byte[0] : readBlob(commandStream, 32L * 1024L * 1024L);
      if (vectors.length % 33 != 0) {
        throw new IllegalArgumentException("command vector stream length " + vectors.length);
      }
      initializeMultiplayerEngine(activePlayers, deathmatch, skill, episode, map);
      String membership = multiplayerMembership(activePlayers);
      String stateSha = initialStateSha;
      byte[] applied = new byte[32];
      int vectorCount = vectors.length / 33;
      for (int vector = 0; vector < vectorCount; vector++) {
        int recordOffset = vector * 33;
        int membershipMask = vectors[recordOffset] & 0xff;
        applyMultiplayerMembership(activePlayers, membershipMask);
        membership = multiplayerMembership(activePlayers, membershipMask);
        Arrays.fill(applied, (byte) 0);
        for (int player = 0; player < activePlayers; player++) {
          int offset = recordOffset + 1 + player * doom.ticcmd_t.TICCMDLEN;
          if (!engine.playeringame[player]) continue;
          int buffer = (engine.gametic / engine.getTicdup())
              % engine.netcmds[player].length;
          doom.ticcmd_t command = engine.netcmds[player][buffer];
          decodeMultiplayerCommand(command, vectors, offset,
              multiplayerConsistency[player][buffer]);
          command.pack(applied, player * doom.ticcmd_t.TICCMDLEN);
        }
        tickMultiplayerEngine();
        stateSha = hashAscii(stateSha + '|' + membership + '|'
            + hex(applied) + '|' + multiplayerStateSha(activePlayers));
        if (vector + 1 < vectorCount) {
          int savedConsole = engine.consoleplayer;
          int savedDisplay = engine.displayplayer;
          try {
            for (int player = 0; player < activePlayers; player++) {
              if (!engine.playeringame[player]) continue;
              engine.consoleplayer = player;
              engine.displayplayer = player;
              engine.Display();
              rememberMultiplayerFrame(player);
            }
          } finally {
            engine.consoleplayer = savedConsole;
            engine.displayplayer = savedDisplay;
          }
        }
      }
      if (!stateSha.equals(expectedStateSha)) {
        throw new IllegalStateException("reconstruction state mismatch actual=" + stateSha);
      }
      return renderMultiplayerPayloads("multiplayer-reconstructed", activePlayers,
          membership, stateSha, new Blob[] {output0, output1, output2, output3})
          + "|replayedVectors=" + vectorCount;
    } catch (Throwable failure) {
      disposeSafe();
      return failure("multiplayer-reconstruct", failure);
    }
  }

  private static void initializeMultiplayerEngine(
      int activePlayers, int deathmatch, int skill, int episode, int map)
      throws Exception {
    if (activePlayers < 2 || activePlayers > 4) {
      throw new IllegalArgumentException("active players " + activePlayers);
    }
    if (deathmatch != 0 && deathmatch != 1) {
      throw new IllegalArgumentException("deathmatch flag " + deathmatch);
    }
    if (skill < 1 || skill > 5 || episode < 1 || episode > 9
        || map < 1 || map > 99) {
      throw new IllegalArgumentException("invalid multiplayer map selection");
    }
    disposeSafe();
    String initialized = initializeSafe();
    if (!initialized.startsWith("ok|")) {
      throw new IllegalStateException(initialized);
    }
    Arrays.fill(engine.playeringame, false);
    for (int player = 0; player < activePlayers; player++) {
      engine.playeringame[player] = true;
    }
    engine.consoleplayer = 0;
    engine.displayplayer = 0;
    engine.netgame = activePlayers > 1;
    engine.deathmatch = deathmatch != 0;
    engine.InitNew(skill_t.values()[skill - 1], episode, map);
    engine.singletics = true;
    controlTurnHeld = 0;
    DummySFX.clearEvents();
    lastAudioJson = "[]";
    multiplayerConsistency = new short[engine.playeringame.length]
        [engine.netcmds[0].length];
    multiplayerPreviousTransport = new byte[engine.playeringame.length][];
    multiplayerTransportScratch = new byte[engine.playeringame.length][];
    multiplayerRawPayload = new byte[engine.playeringame.length][];
    multiplayerPackedPayload = new byte[engine.playeringame.length][];
    multiplayerPayloadLength = new int[engine.playeringame.length];
    multiplayerKeyframeInterval = 4;
    deathmatchFragLimit = deathmatch == 1 ? DEATHMATCH_FRAG_LIMIT : 0;
    deathmatchTimeLimitTics = deathmatch == 1 ? DEATHMATCH_TIME_LIMIT_TICS : 0;
  }

  private static void requireMultiplayerEngine(int activePlayers) {
    if (engine == null || multiplayerConsistency == null
        || activePlayers < 2 || activePlayers > 4 || !engine.netgame) {
      throw new IllegalStateException("multiplayer engine not initialized");
    }
    for (int player = activePlayers; player < engine.playeringame.length; player++) {
      if (engine.playeringame[player]) throw new IllegalStateException(
          "multiplayer allocation mismatch");
    }
  }

  private static void applyMultiplayerMembership(int activePlayers, int mask) {
    int allowed = (1 << activePlayers) - 1;
    if ((mask & 1) == 0 || (mask & ~allowed) != 0) {
      throw new IllegalArgumentException("multiplayer membership mask " + mask);
    }
    for (int player = 0; player < engine.playeringame.length; player++) {
      engine.playeringame[player] = player < activePlayers
          && (mask & (1 << player)) != 0;
    }
  }

  private static String renderMultiplayerPayloads(
      String state, int activePlayers, String membership, String stateSha,
      Blob[] outputs) throws Exception {
    String beforeRender = multiplayerStateSha(activePlayers);
    String sharedAudio = lastAudioJson;
    int savedConsole = engine.consoleplayer;
    int savedDisplay = engine.displayplayer;
    StringBuilder result = new StringBuilder("ok|state=").append(state)
        .append("|tic=").append(engine.gametic)
        .append("|levelTime=").append(engine.leveltime)
        .append("|membership=").append(membership)
        .append("|stateSha256=").append(stateSha);
    try {
      for (int player = 0; player < activePlayers; player++) {
        if (!engine.playeringame[player]) continue;
        Blob output = outputs[player];
        if (output == null) {
          throw new IllegalArgumentException("POV output " + player);
        }
        engine.consoleplayer = player;
        engine.displayplayer = player;
        engine.Display();
        if (engine.doomSound instanceof s.AbstractDoomAudio
            && engine.players[player].mo != null) {
          lastAudioJson = DummySFX.drainEventsFor(engine.gametic,
              (s.AbstractDoomAudio) engine.doomSound, engine.players[player].mo);
        }
        String frameSha = currentFrameSha();
        byte[] payload = encodeMultiplayerFrame(stateSha, frameSha, player);
        int payloadLength = multiplayerPayloadLength[player];
        writeBlob(output, payload, payloadLength);
        MessageDigest responseDigest = MessageDigest.getInstance("SHA-256");
        responseDigest.update(payload, 0, payloadLength);
        String responseSha = hex(responseDigest.digest());
        result.append("|pov").append(player).append("FrameSha=")
            .append(frameSha).append("|pov").append(player)
            .append("ResponseSha=").append(responseSha)
            .append("|pov").append(player).append("Bytes=")
            .append(payloadLength);
        lastAudioJson = sharedAudio;
        if (!beforeRender.equals(multiplayerStateSha(activePlayers))) {
          throw new IllegalStateException(
              "POV render mutated world player=" + player);
        }
      }
    } finally {
      lastAudioJson = sharedAudio;
      engine.consoleplayer = savedConsole;
      engine.displayplayer = savedDisplay;
    }
    result.append("|routeDiag=").append(multiplayerRouteDiagnostic(activePlayers));
    if (engine.deathmatch) result.append("|fragLimit=")
        .append(deathmatchFragLimit).append("|timeLimitTics=")
        .append(deathmatchTimeLimitTics);
    return result.toString();
  }

  /** Private, read-only state for authoring real netgame routes. */
  private static String multiplayerRouteDiagnostic(int activePlayers) {
    StringBuilder result = new StringBuilder();
    for (int slot = 0; slot < activePlayers; slot++) {
      doom.player_t player = engine.players[slot];
      if (slot > 0) result.append(';');
      result.append('p').append(slot).append(',').append(player.playerstate)
          .append(',').append(player.health[0]).append(',')
          .append(player.armorpoints[0]).append(',').append(player.killcount)
          .append(',').append(player.itemcount).append(',')
          .append(player.secretcount).append(',');
      if (player.mo == null) result.append("missing");
      else result.append(player.mo.x).append(',').append(player.mo.y).append(',')
          .append(player.mo.z).append(',')
          .append(Long.toUnsignedString(player.mo.angle));
      result.append(',').append(player.ammo[ammotype_t.am_clip.ordinal()])
          .append(',').append(player.ammo[ammotype_t.am_shell.ordinal()])
          .append(',').append(player.ammo[ammotype_t.am_cell.ordinal()])
          .append(',').append(player.ammo[ammotype_t.am_misl.ordinal()])
          .append(',');
      int keys = 0;
      for (int key = 0; key < player.cards.length; key++) {
        if (player.cards[key]) keys |= 1 << key;
      }
      result.append(keys);
    }
    return result.toString();
  }

  private static String multiplayerMembership(int activePlayers) {
    return multiplayerMembership(activePlayers, (1 << activePlayers) - 1);
  }

  private static String multiplayerMembership(int activePlayers, int mask) {
    StringBuilder result = new StringBuilder(4);
    for (int player = 0; player < 4; player++) {
      result.append(player < activePlayers && (mask & (1 << player)) != 0
          ? '1' : '0');
    }
    return result.toString();
  }

  private static byte[] parseHex(String value, int expectedBytes) {
    if (value == null || value.length() != expectedBytes * 2
        || !value.matches("[0-9a-f]+")) {
      throw new IllegalArgumentException("command vector shape");
    }
    byte[] result = new byte[expectedBytes];
    for (int index = 0; index < expectedBytes; index++) {
      result[index] = (byte) Integer.parseInt(
          value.substring(index * 2, index * 2 + 2), 16);
    }
    return result;
  }

  private static String hashAscii(String value) throws Exception {
    return hex(MessageDigest.getInstance("SHA-256").digest(
        value.getBytes(StandardCharsets.US_ASCII)));
  }

  private static void initializeMultiplayerProbe(int activePlayers)
      throws Exception {
    disposeSafe();
    String initialized = initializeSafe();
    if (!initialized.startsWith("ok|")) {
      throw new IllegalStateException(initialized);
    }
    Arrays.fill(engine.playeringame, false);
    for (int player = 0; player < activePlayers; player++) {
      engine.playeringame[player] = true;
    }
    engine.consoleplayer = 0;
    engine.displayplayer = 0;
    engine.netgame = activePlayers > 1;
    engine.deathmatch = false;
    engine.InitNew(skill_t.sk_medium, 1, 1);
    engine.singletics = true;
    controlTurnHeld = 0;
    DummySFX.clearEvents();
    lastAudioJson = "[]";
    multiplayerConsistency = new short[engine.playeringame.length]
        [engine.netcmds[0].length];
  }

  private static byte[] setMultiplayerCommand(
      int player, int forward, int side, int turn, int buttons) {
    int buffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[player].length;
    doom.ticcmd_t command = engine.netcmds[player][buffer];
    command.forwardmove = (byte) clamp(forward, -127, 127);
    command.sidemove = (byte) clamp(side, -127, 127);
    command.angleturn = (short) clamp(turn, Short.MIN_VALUE, Short.MAX_VALUE);
    command.consistancy = multiplayerConsistency == null ? 0
        : multiplayerConsistency[player][buffer];
    command.chatchar = 0;
    command.buttons = (char) (buttons & 0xff);
    command.lookfly = 0;
    return Arrays.copyOf(command.pack(), doom.ticcmd_t.TICCMDLEN);
  }

  private static void tickMultiplayerEngine() {
    int consistencyBuffer = (engine.gametic / engine.getTicdup())
        % engine.netcmds[0].length;
    DummySFX.beginTic(engine.gametic + 1L);
    engine.Ticker();
    armDeathmatchIntermission();
    if (multiplayerConsistency != null) {
      for (int player = 0; player < engine.playeringame.length; player++) {
        if (!engine.playeringame[player]) continue;
        // Mirror Doom's actual ring word. Usually this is the pre-tick mobj X;
        // on a reborn tic DoReborn replaces the mobj before Doom writes it.
        multiplayerConsistency[player][consistencyBuffer] =
            engine.doomdbConsistency(player, consistencyBuffer);
      }
    }
    engine.gametic++;
    lastAudioJson = DummySFX.drainEvents(engine.gametic);
  }

  private static void armDeathmatchIntermission() {
    if (!engine.deathmatch || engine.gamestate != defines.gamestate_t.GS_LEVEL) {
      return;
    }
    boolean reached = deathmatchTimeLimitTics > 0
        && engine.leveltime >= deathmatchTimeLimitTics;
    for (int player = 0; player < engine.playeringame.length && !reached; player++) {
      if (!engine.playeringame[player]) continue;
      int score = -engine.players[player].frags[player];
      for (int victim = 0; victim < engine.playeringame.length; victim++) {
        if (victim != player) score += engine.players[player].frags[victim];
      }
      reached = deathmatchFragLimit > 0 && score >= deathmatchFragLimit;
    }
    if (reached) engine.ExitLevel();
  }

  /** Decode canonical network-order ticcmd bytes without upstream sign drift. */
  private static void decodeMultiplayerCommand(
      doom.ticcmd_t command, byte[] source, int offset, short consistency) {
    // Upstream ticcmd_t.unpack sign-extends the low byte of both shorts
    // (FEC0 becomes FFC0), so it cannot consume the durable vector ledger.
    command.forwardmove = source[offset];
    command.sidemove = source[offset + 1];
    command.angleturn = (short) (((source[offset + 2] & 0xff) << 8)
        | (source[offset + 3] & 0xff));
    command.consistancy = consistency;
    command.chatchar = 0;
    command.buttons = (char) (source[offset + 7] & 0xff);
    command.lookfly = 0;
  }

  private static String multiplayerStateSha(int activePlayers)
      throws Exception {
    StringBuilder state = new StringBuilder()
        .append(engine.gametic).append('|').append(engine.leveltime).append('|')
        .append(engine.random.getIndex()).append('|')
        .append(engine.netgame).append('|').append(engine.deathmatch);
    for (int player = 0; player < activePlayers; player++) {
      doom.player_t value = engine.players[player];
      state.append('|').append(player).append(':').append(value.playerstate)
          .append(':').append(value.health[0]).append(':')
          .append(Arrays.toString(value.frags));
      if (value.mo == null) state.append(":missing");
      else state.append(':').append(value.mo.x).append(',').append(value.mo.y)
          .append(',').append(value.mo.z).append(',')
          .append(Long.toUnsignedString(value.mo.angle)).append(',')
          .append(value.mo.health);
    }
    return hex(MessageDigest.getInstance("SHA-256").digest(
        state.toString().getBytes(StandardCharsets.US_ASCII)));
  }

  private static int activePlayerMobjCount() {
    int count = 0;
    thinker_t cap = engine.actions.getThinkerCap();
    for (thinker_t thinker = cap.next; thinker != null && thinker != cap;
         thinker = thinker.next) {
      if (thinker instanceof mobj_t && ((mobj_t) thinker).player != null) count++;
    }
    return count;
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
    writeBlob(output, bytes, bytes.length);
  }

  private static void writeBlob(Blob output, byte[] bytes, int length)
      throws Exception {
    if (length < 0 || length > bytes.length) {
      throw new IllegalArgumentException("BLOB byte length " + length);
    }
    output.truncate(0);
    int offset = 0;
    while (offset < length) {
      int count = Math.min(32767, length - offset);
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
    int weapons = 0;
    for (boolean owned : player.weaponowned) if (owned) weapons++;
    int keys = 0;
    for (boolean owned : player.cards) if (owned) keys++;
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
        + "|menu=" + (engine.menuactive ? 1 : 0)
        + "|god=" + ((player.cheats & doom.player_t.CF_GODMODE) != 0 ? 1 : 0)
        + "|noclip=" + ((player.cheats & doom.player_t.CF_NOCLIP) != 0 ? 1 : 0)
        + "|fullmap=" + (player.powers[data.Defines.pw_allmap] != 0 ? 1 : 0)
        + "|ownedWeapons=" + weapons + "|ownedKeys=" + keys
        + "|kills=" + player.killcount + '/' + engine.totalkills
        + "|items=" + player.itemcount + '/' + engine.totalitems
        + "|secrets=" + player.secretcount + '/' + engine.totalsecret
        + "|armor=" + player.armorpoints[0]
        + "|ammo=" + player.ammo[ammotype_t.am_clip.ordinal()] + ','
            + player.ammo[ammotype_t.am_shell.ordinal()] + ','
            + player.ammo[ammotype_t.am_cell.ordinal()] + ','
            + player.ammo[ammotype_t.am_misl.ordinal()]
        + playerState
        + "|nearby=" + nearbyMobjs(player)
        + "|width=" + engine.graphicSystem.getScreenWidth()
        + "|height=" + engine.graphicSystem.getScreenHeight()
        + "|frameBytes=" + pixels.length + "|frameSha256=" + frameSha;
  }

  /** Compact, read-only route-authoring diagnostics ordered by player distance. */
  private static String nearbyMobjs(doom.player_t player) {
    if (player.mo == null) return "NONE";
    final int playerX = player.mo.x;
    final int playerY = player.mo.y;
    ArrayList<mobj_t> nearby = new ArrayList<mobj_t>();
    thinker_t cap = engine.actions.getThinkerCap();
    int examined = 0;
    for (thinker_t thinker = cap.next; thinker != null && thinker != cap;
         thinker = thinker.next) {
      if (++examined > 8192) break;
      if (!(thinker instanceof mobj_t)) continue;
      mobj_t mobj = (mobj_t) thinker;
      if (mobj == player.mo || mobj.type == null) continue;
      if ((mobj.flags & (mobj_t.MF_SPECIAL | mobj_t.MF_SHOOTABLE
          | mobj_t.MF_MISSILE)) == 0) continue;
      long dx = ((long) mobj.x - playerX) >> 16;
      long dy = ((long) mobj.y - playerY) >> 16;
      if (dx * dx + dy * dy <= 1024L * 1024L) nearby.add(mobj);
    }
    Collections.sort(nearby, new Comparator<mobj_t>() {
      public int compare(mobj_t left, mobj_t right) {
        long ldx = ((long) left.x - playerX) >> 16;
        long ldy = ((long) left.y - playerY) >> 16;
        long rdx = ((long) right.x - playerX) >> 16;
        long rdy = ((long) right.y - playerY) >> 16;
        return Long.compare(ldx * ldx + ldy * ldy, rdx * rdx + rdy * rdy);
      }
    });
    StringBuilder result = new StringBuilder();
    int count = Math.min(24, nearby.size());
    for (int index = 0; index < count; index++) {
      mobj_t mobj = nearby.get(index);
      if (index > 0) result.append(';');
      result.append(mobj.type.name()).append('@')
          .append(mobj.x >> 16).append(',').append(mobj.y >> 16)
          .append(',').append(mobj.z >> 16).append(',').append(mobj.health);
    }
    return result.length() == 0 ? "NONE" : result.toString();
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
        + player.armorpoints[0] + '|' + player.readyweapon.name() + '|'
        + player.pendingweapon.name() + '|' + player.viewz + '|'
        + player.cheats + '|' + Arrays.toString(player.weaponowned) + '|'
        + Arrays.toString(player.ammo) + '|' + Arrays.toString(player.cards) + '|'
        + Arrays.toString(player.powers) + '|' + lastAudioJson;
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
    // Byte 9 is the level-completion flag: vanilla G_DoCompleted moves
    // gamestate off GS_LEVEL once the exit tic commits, so intermission and
    // finale frames report complete=1 while normal play reports 0.
    payload[9] = (byte)
        (engine.gamestate == defines.gamestate_t.GS_LEVEL ? 0 : 1);
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

  private static byte[] encodeDmf4(String stateSha, String frameSha)
      throws Exception {
    byte[] raw = encodeDmf3(stateSha, frameSha);
    return packDmf(raw, (byte) '4');
  }

  private static byte[] encodeMultiplayerFrame(
      String stateSha, String frameSha, int player) throws Exception {
    byte[] pixels = currentFrame();
    if (pixels.length != 320 * 200) {
      throw new IllegalStateException("DMF3 requires 320x200 indexed frame");
    }
    byte[] audio = lastAudioJson.getBytes(StandardCharsets.US_ASCII);
    if (audio.length > 65535) {
      throw new IllegalStateException("DMF3 audio payload too large");
    }
    int frameStart = 140 + audio.length;
    int rawLength = frameStart + pixels.length;
    byte[] raw = multiplayerRawPayload[player];
    if (raw == null) {
      raw = new byte[MULTIPLAYER_PAYLOAD_CAPACITY];
      multiplayerRawPayload[player] = raw;
    }
    raw[0] = 'D'; raw[1] = 'M'; raw[2] = 'F'; raw[3] = '3';
    int tic = engine.gametic;
    raw[4] = (byte) (tic >>> 24);raw[5] = (byte) (tic >>> 16);
    raw[6] = (byte) (tic >>> 8);raw[7] = (byte) tic;
    doom.player_t active = engine.players[engine.consoleplayer];
    raw[8] = (byte) (active.health[0] <= 0 ? 1 : 0);
    raw[9] = (byte)
        (engine.gamestate == defines.gamestate_t.GS_LEVEL ? 0 : 1);
    byte[] stateBytes = stateSha.getBytes(StandardCharsets.US_ASCII);
    byte[] frameBytes = frameSha.getBytes(StandardCharsets.US_ASCII);
    System.arraycopy(stateBytes, 0, raw, 10, 64);
    System.arraycopy(frameBytes, 0, raw, 74, 64);
    raw[138] = (byte) (audio.length >>> 8);raw[139] = (byte) audio.length;
    System.arraycopy(audio, 0, raw, 140, audio.length);
    byte[] previous = multiplayerPreviousTransport[player];
    byte[] current = multiplayerTransportScratch[player];
    if (current == null || current.length != pixels.length) {
      current = new byte[pixels.length];
    }
    boolean keyframe = engine.gametic == 0
        || engine.gametic % multiplayerKeyframeInterval == 1
        || previous == null || previous.length != current.length;
    int transport = 0;
    for (int x = 0; x < 320; x++) {
      for (int y = 0; y < 200; y++) {
        byte value = pixels[y * 320 + x];
        current[transport] = value;
        raw[frameStart + transport] = keyframe ? value
            : (byte) (value ^ previous[transport]);
        transport++;
      }
    }
    multiplayerPreviousTransport[player] = current;
    multiplayerTransportScratch[player] = previous;
    return packMultiplayerDmf(raw, rawLength, frameStart,
        (byte) (keyframe ? '4' : '5'), player);
  }

  private static void rememberMultiplayerFrame(int player) throws Exception {
    byte[] pixels = currentFrame();
    byte[] transport = multiplayerTransportScratch[player];
    if (transport == null || transport.length != pixels.length) {
      transport = new byte[pixels.length];
    }
    int offset = 0;
    for (int x = 0; x < 320; x++) {
      for (int y = 0; y < 200; y++) transport[offset++] = pixels[y * 320 + x];
    }
    byte[] previous = multiplayerPreviousTransport[player];
    multiplayerPreviousTransport[player] = transport;
    multiplayerTransportScratch[player] = previous;
  }

  private static byte[] packMultiplayerDmf(
      byte[] raw, int rawLength, int frameStart, byte magic, int player) {
    int maximumLength = rawLength + ((rawLength - frameStart + 127) / 128) + 1;
    if (maximumLength > MULTIPLAYER_PAYLOAD_CAPACITY) {
      throw new IllegalStateException("multiplayer payload workspace " + maximumLength);
    }
    byte[] packed = multiplayerPackedPayload[player];
    if (packed == null) {
      packed = new byte[MULTIPLAYER_PAYLOAD_CAPACITY];
      multiplayerPackedPayload[player] = packed;
    }
    System.arraycopy(raw, 0, packed, 0, frameStart);
    packed[3] = magic;
    int source = frameStart, target = frameStart;
    while (source < rawLength) {
      int run = 1;
      while (source + run < rawLength && raw[source + run] == raw[source]
          && run < 128) run++;
      if (run >= 3) {
        packed[target++] = (byte) (0x80 | (run - 1));
        packed[target++] = raw[source];source += run;continue;
      }
      int literalStart = source;
      source += run;
      while (source < rawLength && source - literalStart < 128) {
        run = 1;
        while (source + run < rawLength && raw[source + run] == raw[source]
            && run < 128) run++;
        if (run >= 3 || source - literalStart + run > 128) break;
        source += run;
      }
      int literalLength = source - literalStart;
      packed[target++] = (byte) (literalLength - 1);
      System.arraycopy(raw, literalStart, packed, target, literalLength);
      target += literalLength;
    }
    if (magic == '4' && target >= rawLength) {
      multiplayerPayloadLength[player] = rawLength;return raw;
    }
    multiplayerPayloadLength[player] = target;return packed;
  }

  private static byte[] packDmf(byte[] raw, byte magic) throws Exception {
    int frameStart = 140 + ((raw[138] & 0xff) << 8) + (raw[139] & 0xff);
    ByteArrayOutputStream output = new ByteArrayOutputStream(raw.length);
    output.write(raw, 0, frameStart);
    byte[] header = output.toByteArray();
    header[3] = magic;
    output.reset();
    output.write(header, 0, header.length);
    int source = frameStart;
    while (source < raw.length) {
      int run = 1;
      while (source + run < raw.length && raw[source + run] == raw[source]
          && run < 128) run++;
      if (run >= 3) {
        output.write(0x80 | (run - 1));
        output.write(raw[source] & 0xff);
        source += run;
        continue;
      }
      int literalStart = source;
      source += run;
      while (source < raw.length && source - literalStart < 128) {
        run = 1;
        while (source + run < raw.length && raw[source + run] == raw[source]
            && run < 128) run++;
        if (run >= 3 || source - literalStart + run > 128) break;
        source += run;
      }
      int literalLength = source - literalStart;
      output.write(literalLength - 1);
      output.write(raw, literalStart, literalLength);
    }
    byte[] packed = output.toByteArray();
    if (packed.length < raw.length) return packed;
    // A full frame can fall back to DMF3. A delta must retain its DMF5 marker
    // even when an unusually noisy transition does not shrink.
    return magic == '4' ? raw : packed;
  }

  private static void applyControlFlags(int flags) {
    if ((flags & 0x02) != 0) {
      if (engine.automapactive) engine.autoMap.Stop();
      else engine.autoMap.Start();
    }
    if ((flags & 0x04) != 0) {
      if (engine.menuactive) engine.menu.ClearMenus();
      else engine.menu.StartControlPanel();
    }
    int cheat = (flags >>> 3) & 0x07;
    doom.player_t player = engine.players[engine.consoleplayer];
    if (cheat == 1) {
      player.cheats ^= doom.player_t.CF_GODMODE;
      if ((player.cheats & doom.player_t.CF_GODMODE) != 0) {
        player.health[0] = 100;
        if (player.mo != null) player.mo.health = 100;
      }
    } else if (cheat == 2) {
      player.armorpoints[0] = 200;
      player.armortype = 2;
      Arrays.fill(player.weaponowned, true);
      System.arraycopy(player.maxammo, 0, player.ammo, 0, player.ammo.length);
      Arrays.fill(player.cards, true);
    } else if (cheat == 3) {
      player.cheats ^= doom.player_t.CF_NOCLIP;
    } else if (cheat == 4) {
      player.powers[data.Defines.pw_allmap] =
          player.powers[data.Defines.pw_allmap] == 0 ? 1 : 0;
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
