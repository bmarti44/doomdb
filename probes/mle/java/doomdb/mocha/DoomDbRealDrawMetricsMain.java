/*
 * Copyright (C) 2026 DoomDB contributors
 * GPLv3-or-later. Disposable real-frame renderer instrumentation.
 */
package doomdb.mocha;

import data.Tables;
import defines.skill_t;
import doom.DoomMain;
import doom.player_t;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import mochadoom.Engine;
import s.DummySFX;
import w.InputStreamSugar;

/**
 * Runs the production Mocha raster functions against a real IWAD and moving,
 * firing E1M1 route. This is deliberately a plain-JVM diagnostic: it captures
 * workload shape without changing the MLE or database artifacts being ranked.
 */
public final class DoomDbRealDrawMetricsMain {
  private DoomDbRealDrawMetricsMain() {}

  public static void main(String[] args) throws Exception {
    if (args.length >= 3 && args.length <= 5) {
      boolean extendedPoses = args.length == 5
          && "--extended-poses".equals(args[4]);
      if (args.length == 5 && !extendedPoses) {
        throw new IllegalArgumentException("unknown pose format " + args[4]);
      }
      runCanonicalMultiplayer(
          args[0], args[1], args[2], args.length >= 4 ? args[3] : null,
          extendedPoses);
      return;
    }
    if (args.length != 7) {
      throw new IllegalArgumentException(
          "usage: IWAD STREAM TABLES or "
          + "IWAD samples warmups forward side turn fireEvery");
    }
    byte[] iwad = Files.readAllBytes(Paths.get(args[0]));
    int samples = Integer.parseInt(args[1]);
    int warmups = Integer.parseInt(args[2]);
    int forward = Integer.parseInt(args[3]);
    int side = Integer.parseInt(args[4]);
    int turn = Integer.parseInt(args[5]);
    int fireEvery = Integer.parseInt(args[6]);
    if (samples < 1 || samples > 5250 || warmups < 0 || warmups > 1000) {
      throw new IllegalArgumentException("sample or warmup bound");
    }

    Tables.InitTables();
    InputStreamSugar.setInjectedResource(iwad);
    DoomMain<?, ?> engine = Engine.createHeadless(
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200");
    try {
      engine.singletics = true;
      engine.InitNew(skill_t.sk_medium, 1, 1);
      engine.Display();
      DoomDbDrawMetrics.beginRun();
      long started = System.nanoTime();
      for (int index = -warmups; index < samples; index++) {
        int buffer = (engine.gametic / engine.getTicdup())
            % engine.netcmds[engine.consoleplayer].length;
        doom.ticcmd_t command = engine.netcmds[engine.consoleplayer][buffer];
        command.forwardmove = (byte) clamp(forward, -127, 127);
        command.sidemove = (byte) clamp(side, -127, 127);
        command.angleturn = (short) clamp(turn, Short.MIN_VALUE, Short.MAX_VALUE);
        command.buttons = (char) (fireEvery > 0
            && Math.floorMod(index + warmups, fireEvery) == 0 ? 1 : 0);
        command.chatchar = 0;
        command.lookfly = 0;
        DummySFX.beginTic(engine.gametic + 1L);
        engine.Ticker();
        engine.gametic++;
        DummySFX.drainEvents(engine.gametic);
        if (index >= 0) DoomDbDrawMetrics.beginFrame();
        engine.Display();
        if (index >= 0) DoomDbDrawMetrics.endFrame();
      }
      long elapsedMicros = (System.nanoTime() - started) / 1000L;
      System.out.println("PMLE_REAL_DRAW_METRICS|PASS|samples=" + samples
          + "|warmups=" + warmups + "|elapsedMicros=" + elapsedMicros
          + "|" + DoomDbDrawMetrics.finish());
    } finally {
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
    }
  }

  private static void runCanonicalMultiplayer(
      String iwadPath, String streamPath, String tablePath, String posePath,
      boolean extendedPoses)
      throws Exception {
    byte[] iwad = Files.readAllBytes(Paths.get(iwadPath));
    byte[] stream = Files.readAllBytes(Paths.get(streamPath));
    byte[] tables = Files.readAllBytes(Paths.get(tablePath));
    if (stream.length != 5250 * 33) {
      throw new IllegalArgumentException("canonical stream bytes " + stream.length);
    }
    Tables.installCanonicalTablePack(tables);
    InputStreamSugar.setInjectedResource(iwad);
    DoomMain<?, ?> engine = Engine.createHeadless(
        "-iwad", "freedoom1.wad", "-nosound", "-nomusic", "-indexed",
        "-width", "320", "-height", "200");
    try {
      for (int player = 0; player < engine.playeringame.length; player++) {
        engine.playeringame[player] = player < 2;
      }
      engine.consoleplayer = 0;
      engine.displayplayer = 0;
      engine.netgame = true;
      engine.deathmatch = true;
      engine.InitNew(skill_t.sk_hard, 1, 1);
      engine.singletics = true;
      engine.sceneRenderer.SetViewSize(10, 0);
      short[][] consistency = new short[engine.playeringame.length]
          [engine.netcmds[0].length];
      engine.Display();
      DoomDbDrawMetrics.beginRun();
      ByteArrayOutputStream poses = posePath == null
          ? null : new ByteArrayOutputStream(5250 * (extendedPoses ? 32 : 12));
      long started = System.nanoTime();
      for (int tic = 0; tic < 5250; tic++) {
        int offset = tic * 33;
        int membership = stream[offset] & 0xff;
        for (int player = 0; player < engine.playeringame.length; player++) {
          engine.playeringame[player] =
              player < 2 && (membership & (1 << player)) != 0;
        }
        int buffer = (engine.gametic / engine.getTicdup())
            % engine.netcmds[0].length;
        for (int player = 0; player < 4; player++) {
          int commandOffset = offset + 1 + player * doom.ticcmd_t.TICCMDLEN;
          doom.ticcmd_t command = engine.netcmds[player][buffer];
          command.forwardmove = stream[commandOffset];
          command.sidemove = stream[commandOffset + 1];
          command.angleturn = (short) (((stream[commandOffset + 2] & 0xff) << 8)
              | (stream[commandOffset + 3] & 0xff));
          command.consistancy = consistency[player][buffer];
          command.chatchar = (char) (stream[commandOffset + 6] & 0xff);
          command.buttons = (char) (stream[commandOffset + 7] & 0xff);
          command.lookfly = 0;
        }
        engine.Ticker();
        for (int player = 0; player < 2; player++) {
          consistency[player][buffer] = engine.doomdbConsistency(player, buffer);
        }
        engine.gametic++;
        if (poses != null) {
          player_t player = engine.players[engine.displayplayer];
          if (player.mo == null) {
            throw new IllegalStateException("display player has no mobj at tic " + tic);
          }
          writeLittleEndianInt(poses, player.mo.x);
          writeLittleEndianInt(poses, player.mo.y);
          writeLittleEndianInt(poses, (int) (player.mo.angle >>> 16));
          if (extendedPoses) {
            writeLittleEndianInt(poses, player.viewz);
            writeLittleEndianInt(poses, player.health[0]);
            writeLittleEndianInt(poses, player.armorpoints[0]);
            writeLittleEndianInt(poses, player.readyweapon.ordinal());
            writeLittleEndianInt(poses, player.ammo[0]);
          }
        }
        DoomDbDrawMetrics.beginFrame();
        engine.Display();
        DoomDbDrawMetrics.endFrame();
      }
      long elapsedMicros = (System.nanoTime() - started) / 1000L;
      System.out.println("PMLE_REAL_DRAW_METRICS|PASS|stream=live-dm-2026-07-23"
          + "|samples=5250|elapsedMicros=" + elapsedMicros
          + "|streamSha256=" + hex(MessageDigest.getInstance("SHA-256")
              .digest(stream))
          + "|" + DoomDbDrawMetrics.finish());
      if (poses != null) {
        byte[] poseBytes = poses.toByteArray();
        Files.write(Paths.get(posePath), poseBytes);
        System.out.println("PMLE_REAL_DRAW_POSES|PASS|records=5250|bytes="
            + poseBytes.length + "|sha256="
            + hex(MessageDigest.getInstance("SHA-256").digest(poseBytes))
            + "|recordBytes=" + (extendedPoses ? 32 : 12));
      }
    } finally {
      Engine.releaseHeadless();
      InputStreamSugar.clearInjectedResource();
    }
  }

  private static String hex(byte[] bytes) {
    StringBuilder result = new StringBuilder(bytes.length * 2);
    for (byte value : bytes) {
      result.append(String.format("%02x", value & 0xff));
    }
    return result.toString();
  }

  private static int clamp(int value, int minimum, int maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private static void writeLittleEndianInt(ByteArrayOutputStream output, int value) {
    output.write(value & 0xff);
    output.write((value >>> 8) & 0xff);
    output.write((value >>> 16) & 0xff);
    output.write((value >>> 24) & 0xff);
  }
}
