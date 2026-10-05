/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the name of 'LWJGL' nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
package org.lwjgl.opengl;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;

import org.lwjgl.input.Mouse;

/**
 * Kostka: the mouse made of touches. The native side sends positions while the mouse is free (menus) and
 * movements while it is grabbed (looking around in a game); this keeps LWJGL's mouse state and event queue.
 */
final class IOSMouse extends EventQueue {
	static final int NUM_BUTTONS = 3;

	private final ByteBuffer event = ByteBuffer.allocate(Mouse.EVENT_SIZE);
	private final byte[] buttons = new byte[NUM_BUTTONS];
	private boolean grabbed;
	private int last_x;
	private int last_y;
	private int accum_dx;
	private int accum_dy;
	private int accum_dz;

	IOSMouse(int x, int y) {
		super(Mouse.EVENT_SIZE);
		last_x = x;
		last_y = y;
	}

	synchronized void setGrabbed(boolean grabbed) {
		this.grabbed = grabbed;
		accum_dx = accum_dy = 0;
	}

	synchronized void setPosition(int x, int y) {
		last_x = x;
		last_y = y;
	}

	synchronized void poll(IntBuffer coord_buffer, ByteBuffer buttons_buffer) {
		if (grabbed) {
			coord_buffer.put(0, accum_dx);
			coord_buffer.put(1, accum_dy);
		} else {
			coord_buffer.put(0, last_x);
			coord_buffer.put(1, last_y);
		}
		coord_buffer.put(2, accum_dz);
		accum_dx = accum_dy = accum_dz = 0;
		int old_position = buttons_buffer.position();
		buttons_buffer.put(buttons, 0, buttons.length);
		buttons_buffer.position(old_position);
	}

	/** A finger at a position (free mouse) */
	synchronized void moveTo(int x, int y, long nanos) {
		accum_dx += x - last_x;
		accum_dy += y - last_y;
		last_x = x;
		last_y = y;
		if (!grabbed)
			put((byte)-1, (byte)0, x, y, 0, nanos);
	}

	/** A finger moved by so much (grabbed mouse) */
	synchronized void moveBy(int dx, int dy, long nanos) {
		accum_dx += dx;
		accum_dy += dy;
		if (grabbed)
			put((byte)-1, (byte)0, dx, dy, 0, nanos);
	}

	synchronized void setButton(int button, int state, long nanos) {
		if (button < 0 || button >= NUM_BUTTONS)
			return;
		buttons[button] = (byte)state;
		put((byte)button, (byte)state, grabbed ? 0 : last_x, grabbed ? 0 : last_y, 0, nanos);
	}

	synchronized void scroll(int dz, long nanos) {
		accum_dz += dz;
		put((byte)-1, (byte)0, grabbed ? 0 : last_x, grabbed ? 0 : last_y, dz, nanos);
	}

	private void put(byte button, byte state, int coord1, int coord2, int dz, long nanos) {
		event.clear();
		event.put(button).put(state).putInt(coord1).putInt(coord2).putInt(dz).putLong(nanos);
		event.flip();
		putEvent(event);
	}
}
