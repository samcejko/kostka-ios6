/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.Point;
import java.awt.Rectangle;
import java.awt.Window;
import java.awt.peer.MouseInfoPeer;
import java.awt.peer.RobotPeer;
import java.lang.reflect.Method;

/**
 * Kostka's AWT: the mouse pointer of AWT is LWJGL's (the touches): MouseInfo reads it, a Robot moves it. On iOS the
 * windows are all at the screen's origin, so AWT's screen and LWJGL's window are one (y turned upside down).
 * Minecraft Classic turns the view this way: it reads the pointer, then puts it back in the middle.
 * (LWJGL is in the application's class path, this in the boot one: it is reached by reflection.)
 */
final class KPointer {
	private static Method getX, getY, setCursorPosition, getHeight;
	private static boolean looked;

	private static synchronized boolean lwjgl() {
		if (!looked) {
			looked = true;
			try {
				ClassLoader cl = ClassLoader.getSystemClassLoader();
				Class<?> mouse = Class.forName("org.lwjgl.input.Mouse", false, cl);
				Class<?> display = Class.forName("org.lwjgl.opengl.Display", false, cl);
				getX = mouse.getMethod("getX");
				getY = mouse.getMethod("getY");
				setCursorPosition = mouse.getMethod("setCursorPosition", int.class, int.class);
				getHeight = display.getMethod("getHeight");
			} catch (Throwable t) {
				getX = null;
			}
		}
		return getX != null;
	}

	static void where(Point p) {
		p.x = p.y = 0;
		if (!lwjgl())
			return;
		try {
			int h = ((Integer)getHeight.invoke(null)).intValue();
			p.x = ((Integer)getX.invoke(null)).intValue();
			p.y = h - 1 - ((Integer)getY.invoke(null)).intValue();
		} catch (Throwable t) {
			// (no Display yet)
		}
	}

	static void move(int x, int y) {
		if (!lwjgl())
			return;
		try {
			int h = ((Integer)getHeight.invoke(null)).intValue();
			setCursorPosition.invoke(null, Integer.valueOf(x), Integer.valueOf(h - 1 - y));
		} catch (Throwable t) {
			// (no mouse yet)
		}
	}

	/** MouseInfo's peer */
	static final class Info implements MouseInfoPeer {
		public int fillPointWithCoords(Point point) {
			where(point);
			return 0;
		}

		public boolean isWindowUnderMouse(Window w) {
			return w != null && w.isShowing();
		}
	}

	/** A Robot's peer: it moves the pointer; it has no keys to press and no screen to read */
	static final class Robot implements RobotPeer {
		public void mouseMove(int x, int y) {
			move(x, y);
		}

		public void mousePress(int buttons) {
		}

		public void mouseRelease(int buttons) {
		}

		public void mouseWheel(int wheelAmt) {
		}

		public void keyPress(int keycode) {
		}

		public void keyRelease(int keycode) {
		}

		public int getRGBPixel(int x, int y) {
			return 0;
		}

		public int[] getRGBPixels(Rectangle bounds) {
			return new int[Math.max(0, bounds.width * bounds.height)];
		}

		public void dispose() {
		}
	}
}
