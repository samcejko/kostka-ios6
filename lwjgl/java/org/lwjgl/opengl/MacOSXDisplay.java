/*
 * Copyright (c) 2002-2008 LWJGL Project
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend)
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

import java.awt.Canvas;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;

import org.lwjgl.LWJGLException;
import org.lwjgl.LWJGLUtil;
import org.lwjgl.input.Cursor;

/**
 * Kostka: the Display on iOS. The window is a UIKit view on an EAGL layer (ios_display.m); the game's
 * OpenGL goes through gl4es to OpenGL ES 2.0. iOS reports os.name "Mac OS X", so this class keeps the name
 * of LWJGL's Mac OS X display, which it replaces (no Cocoa, no AWT).
 *
 * The framebuffer has the size of the requested display mode (the screen's in fullscreen) and is shown
 * scaled to the screen. Touches come back as mouse and keyboard events (ios_display.m decides which).
 */
final class MacOSXDisplay implements DisplayImplementation {
	// One event from the native side: int type, int a, int b, int c, long nanos (native byte order)
	static final int EVENT_SIZE = 24;
	static final int EVENT_MOUSE_MOVE = 1;     // a, b: position (bottom-left origin)
	static final int EVENT_MOUSE_DELTA = 2;    // a, b: movement while the mouse is grabbed
	static final int EVENT_MOUSE_BUTTON = 3;   // a: button, b: 1 down / 0 up
	static final int EVENT_MOUSE_WHEEL = 4;    // a: wheel amount
	static final int EVENT_KEY = 5;            // a: LWJGL key code, b: 1 down / 0 up, c: character
	static final int EVENT_CLOSE = 6;
	static final int EVENT_FOCUS = 7;          // a: 1 in front / 0 in the background

	private static final int MAX_EVENTS = 256;
	// (cursors: there is no pointer to draw, but a game that hides it - an empty cursor, as Minecraft Classic does
	// while playing instead of grabbing the mouse - gets the same touches as a grabbed mouse)
	private static final Long CURSOR = Long.valueOf(1);
	private static final Long CURSOR_EMPTY = Long.valueOf(2);

	private final ByteBuffer events = ByteBuffer.allocateDirect(EVENT_SIZE * MAX_EVENTS).order(ByteOrder.nativeOrder());
	private ByteBuffer window;
	private IOSMouse mouse;
	private IOSKeyboard keyboard;
	private boolean close_requested;
	private boolean focused = true;
	private boolean grabbed;
	private boolean cursorHidden;
	private int width;
	private int height;

	MacOSXDisplay() {
	}

	private static native int nGetScreenWidth();

	private static native int nGetScreenHeight();

	private static native ByteBuffer nCreateWindow(int width, int height, boolean fullscreen) throws LWJGLException;

	private static native void nDestroyWindow(ByteBuffer window_handle);

	private static native int nGetWidth(ByteBuffer window_handle);

	private static native int nGetHeight(ByteBuffer window_handle);

	private static native int nPollEvents(ByteBuffer window_handle, ByteBuffer events, int max_events);

	private static native void nSetGrabbed(ByteBuffer window_handle, boolean grabbed);

	/** The native window of the Display, for the context to draw into (null without a window) */
	static ByteBuffer getWindowHandle() {
		DisplayImplementation impl = Display.getImplementation();
		return impl instanceof MacOSXDisplay ? ((MacOSXDisplay)impl).window : null;
	}

	public void createWindow(DrawableLWJGL drawable, DisplayMode mode, Canvas parent, int x, int y) throws LWJGLException {
		close_requested = false;
		window = nCreateWindow(mode.getWidth(), mode.getHeight(), Display.isFullscreen());
		width = nGetWidth(window);
		height = nGetHeight(window);
		touchesForGame();
	}

	public void destroyWindow() {
		if (window != null) {
			nDestroyWindow(window);
			window = null;
		}
	}

	public void switchDisplayMode(DisplayMode mode) throws LWJGLException {
		// (the screen has the one mode)
	}

	public void resetDisplayMode() {
	}

	public int getGammaRampLength() {
		return 0;
	}

	public void setGammaRamp(FloatBuffer gammaRamp) throws LWJGLException {
		throw new LWJGLException("Gamma ramps are not supported");
	}

	public String getAdapter() {
		return null;
	}

	public String getVersion() {
		return null;
	}

	public DisplayMode init() throws LWJGLException {
		return new DisplayMode(nGetScreenWidth(), nGetScreenHeight(), 32, 60);
	}

	public void setTitle(String title) {
		// (no title bar)
	}

	public boolean isCloseRequested() {
		boolean result = close_requested;
		close_requested = false;
		return result;
	}

	public boolean isVisible() {
		return true;
	}

	public boolean isActive() {
		return focused;
	}

	public boolean isDirty() {
		return false;
	}

	public PeerInfo createPeerInfo(PixelFormat pixel_format, ContextAttribs attribs) throws LWJGLException {
		return new MacOSXDisplayPeerInfo(pixel_format, attribs);
	}

	/** Takes the touches and keys that came since the last call (Display.processMessages) */
	public void update() {
		if (window == null)
			return;
		events.clear();
		int count = nPollEvents(window, events, MAX_EVENTS);
		for (int i = 0; i < count; i++) {
			int base = i * EVENT_SIZE;
			int type = events.getInt(base);
			int a = events.getInt(base + 4);
			int b = events.getInt(base + 8);
			int c = events.getInt(base + 12);
			long nanos = events.getLong(base + 16);
			switch (type) {
				case EVENT_MOUSE_MOVE:
					if (mouse != null)
						mouse.moveTo(a, b, nanos);
					break;
				case EVENT_MOUSE_DELTA:
					if (mouse != null)
						mouse.moveBy(a, b, nanos);
					break;
				case EVENT_MOUSE_BUTTON:
					if (mouse != null)
						mouse.setButton(a, b, nanos);
					break;
				case EVENT_MOUSE_WHEEL:
					if (mouse != null)
						mouse.scroll(a, nanos);
					break;
				case EVENT_KEY:
					if (keyboard != null)
						keyboard.putKey(a, b, c, nanos);
					break;
				case EVENT_CLOSE:
					close_requested = true;
					break;
				case EVENT_FOCUS:
					focused = a != 0;
					break;
				default:
					LWJGLUtil.log("Unknown event " + type);
			}
		}
	}

	public void reshape(int x, int y, int width, int height) {
	}

	public DisplayMode[] getAvailableDisplayModes() throws LWJGLException {
		return new DisplayMode[] { new DisplayMode(nGetScreenWidth(), nGetScreenHeight(), 32, 60) };
	}

	/* Pbuffers: not on iOS (render to a framebuffer object instead) */
	public int getPbufferCapabilities() {
		return 0;
	}

	public boolean isBufferLost(PeerInfo handle) {
		return false;
	}

	public PeerInfo createPbuffer(int width, int height, PixelFormat pixel_format, ContextAttribs attribs,
			IntBuffer pixelFormatCaps, IntBuffer pBufferAttribs) throws LWJGLException {
		throw new LWJGLException("Pbuffers are not supported");
	}

	public void setPbufferAttrib(PeerInfo handle, int attrib, int value) {
		throw new UnsupportedOperationException();
	}

	public void bindTexImageToPbuffer(PeerInfo handle, int buffer) {
		throw new UnsupportedOperationException();
	}

	public void releaseTexImageFromPbuffer(PeerInfo handle, int buffer) {
		throw new UnsupportedOperationException();
	}

	public int setIcon(ByteBuffer[] icons) {
		return 0;
	}

	public void setResizable(boolean resizable) {
	}

	public boolean wasResized() {
		return false;
	}

	public int getWidth() {
		return width;
	}

	public int getHeight() {
		return height;
	}

	public int getX() {
		return 0;
	}

	public int getY() {
		return 0;
	}

	public float getPixelScaleFactor() {
		return 1f;
	}

	/* Mouse */
	public boolean hasWheel() {
		return true;
	}

	public int getButtonCount() {
		return IOSMouse.NUM_BUTTONS;
	}

	public void createMouse() throws LWJGLException {
		mouse = new IOSMouse(width, height);
	}

	public void destroyMouse() {
		grabMouse(false);
		mouse = null;
	}

	public void pollMouse(IntBuffer coord_buffer, ByteBuffer buttons_buffer) {
		mouse.poll(coord_buffer, buttons_buffer);
	}

	public void readMouse(ByteBuffer buffer) {
		mouse.copyEvents(buffer);
	}

	public void grabMouse(boolean grab) {
		grabbed = grab;
		if (mouse != null)
			mouse.setGrabbed(grab);
		touchesForGame();
	}

	/** The touches look around (and the moving keys show) while the mouse is grabbed or its cursor hidden */
	private void touchesForGame() {
		if (window != null)
			nSetGrabbed(window, grabbed || cursorHidden);
	}

	public int getNativeCursorCapabilities() {
		return Cursor.CURSOR_ONE_BIT_TRANSPARENCY | Cursor.CURSOR_8_BIT_ALPHA | Cursor.CURSOR_ANIMATION;
	}

	public void setCursorPosition(int x, int y) {
		if (mouse != null)
			mouse.setPosition(x, y);
	}

	public void setNativeCursor(Object handle) throws LWJGLException {
		cursorHidden = CURSOR_EMPTY.equals(handle);
		touchesForGame();
	}

	public int getMinCursorSize() {
		return 1;
	}

	public int getMaxCursorSize() {
		return 256;
	}

	/* Keyboard */
	public void createKeyboard() throws LWJGLException {
		keyboard = new IOSKeyboard();
	}

	public void destroyKeyboard() {
		keyboard = null;
	}

	public void pollKeyboard(ByteBuffer keyDownBuffer) {
		keyboard.poll(keyDownBuffer);
	}

	public void readKeyboard(ByteBuffer buffer) {
		keyboard.copyEvents(buffer);
	}

	public Object createCursor(int width, int height, int xHotspot, int yHotspot, int numImages, IntBuffer images, IntBuffer delays) throws LWJGLException {
		for (int i = images.position(); i < images.limit(); i++) {
			if ((images.get(i) >>> 24) != 0)
				return CURSOR;
		}
		return CURSOR_EMPTY;
	}

	public void destroyCursor(Object cursor_handle) {
	}

	public boolean isInsideWindow() {
		return true;
	}
}
