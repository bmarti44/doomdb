/*
 * Copyright (C) 2026 DoomDB contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */
package doomdb.mocha;

/** Converts upstream process exits into catchable OJVM call failures. */
public final class OjvmExit {
  private OjvmExit() {}

  public static void block(int status) {
    throw new IllegalStateException("System.exit blocked: " + status);
  }
}
