/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.Component;
import java.awt.Window;
import java.awt.peer.KeyboardFocusManagerPeer;

/** Kostka's AWT: the focus, which only AWT itself keeps track of (the game's keys come through LWJGL) */
public class KFocusPeer implements KeyboardFocusManagerPeer {
	private Window window;
	private Component owner;

	public synchronized void setCurrentFocusedWindow(Window win) {
		window = win;
	}

	public synchronized Window getCurrentFocusedWindow() {
		return window;
	}

	public synchronized void setCurrentFocusOwner(Component comp) {
		owner = comp;
	}

	public synchronized Component getCurrentFocusOwner() {
		return owner;
	}

	public synchronized void clearGlobalFocusOwner(Window activeWindow) {
		owner = null;
	}
}
