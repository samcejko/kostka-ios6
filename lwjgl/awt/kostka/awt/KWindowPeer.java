/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.Dialog;
import java.awt.Frame;
import java.awt.MenuBar;
import java.awt.Rectangle;
import java.awt.Window;
import java.awt.event.WindowEvent;
import java.awt.peer.DialogPeer;
import java.awt.peer.FramePeer;
import java.util.List;

import sun.awt.AWTAccessor;
import sun.awt.SunToolkit;

/**
 * Kostka's AWT: a window (frame, dialog) that exists without being drawn. Shown, it tells AWT it was opened and
 * activated, as a real window system would. And it takes the whole screen, as a window system that maximizes every
 * window would: an iPad shows one at a time, and old Minecraft's frame (launchwrapper's, 854x480) then gives the
 * game the screen's size, with no bars above and below it.
 */
public class KWindowPeer extends KComponentPeer implements FramePeer, DialogPeer {
	private int state = Frame.NORMAL;
	private Rectangle maximized;

	KWindowPeer(Window target) {
		super(target);
	}

	public void setBounds(int x, int y, int width, int height, int op) {
		int w = KToolkit.screenWidth(), h = KToolkit.screenHeight();
		super.setBounds(0, 0, w, h, op);
		// (AWT has taken the asked bounds already: the window's own become the screen's, and its layout follows)
		if (x != 0 || y != 0 || width != w || height != h) {
			AWTAccessor.ComponentAccessor window = AWTAccessor.getComponentAccessor();
			window.setLocation(target, 0, 0);
			window.setSize(target, w, h);
		}
	}

	/** (on iOS every window is at the screen's origin: AWT's screen is then LWJGL's window, see KPointer) */
	public java.awt.Point getLocationOnScreen() {
		return new java.awt.Point(0, 0);
	}

	public void setVisible(boolean v) {
		boolean was = visible;
		super.setVisible(v);
		if (v && !was) {
			Window w = (Window)target;
			SunToolkit.postEvent(SunToolkit.targetToAppContext(w), new WindowEvent(w, WindowEvent.WINDOW_OPENED));
			SunToolkit.postEvent(SunToolkit.targetToAppContext(w), new WindowEvent(w, WindowEvent.WINDOW_ACTIVATED));
		}
	}

	/* WindowPeer */

	public void toFront() {
	}

	public void toBack() {
	}

	public void updateAlwaysOnTopState() {
	}

	public void updateFocusableWindowState() {
	}

	public void setModalBlocked(Dialog blocker, boolean blocked) {
	}

	public void updateMinimumSize() {
	}

	public void updateIconImages() {
	}

	public void setOpacity(float opacity) {
	}

	public void setOpaque(boolean isOpaque) {
	}

	public void updateWindow() {
	}

	public void repositionSecurityWarning() {
	}

	/* FramePeer, DialogPeer */

	public void setTitle(String title) {
	}

	public void setMenuBar(MenuBar mb) {
	}

	public void setResizable(boolean resizeable) {
	}

	public void setState(int state) {
		this.state = state;
	}

	public int getState() {
		return state;
	}

	public void setMaximizedBounds(Rectangle bounds) {
		maximized = bounds;
	}

	public void setBoundsPrivate(int x, int y, int width, int height) {
		setBounds(x, y, width, height, SET_BOUNDS);
	}

	public Rectangle getBoundsPrivate() {
		return new Rectangle(bounds);
	}

	public void emulateActivation(boolean activate) {
	}

	public void blockWindows(List<Window> windows) {
	}
}
