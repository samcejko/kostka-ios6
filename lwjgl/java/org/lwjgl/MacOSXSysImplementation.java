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
package org.lwjgl;

/**
 * Kostka: LWJGL's system services on iOS. iOS (os.name "iPhone OS X") is LWJGL's Mac OS X platform here, and
 * Kostka replaces its Mac OS X classes with ones on UIKit (no AWT, no Swing, no Cocoa).
 */
final class MacOSXSysImplementation extends DefaultSysImplementation {
	private static final int JNI_VERSION = 25;

	public int getRequiredJNIVersion() {
		return JNI_VERSION;
	}

	/** A thread's clock: what it has had taken out, where it was last read, when it last jumped by over a second */
	private static final class Clock {
		long lost, last = Long.MIN_VALUE, slow = Long.MIN_VALUE;
	}

	private static final ThreadLocal<Clock> CLOCKS = new ThreadLocal<Clock>() {
		protected Clock initialValue() {
			return new Clock();
		}
	};

	/**
	 * A monotonic clock in milliseconds: games time their frames with it. Minecraft (1.3 to 1.11) takes a step of
	 * more than a second between two frames for a clock that was set, and lets that frame's time go: a game whose
	 * every frame takes longer - a post-processing shader too much for the iPad 2's graphics (1.8's ntsc, 3 seconds)
	 * - never moves again, clicks and keys included. So from the second such step within 5 seconds on a thread, its
	 * clock goes on by 0.9 seconds: the game runs slowly instead of standing still. A single step (a long garbage
	 * collection) and a pause of more than 10 seconds (the app in the background) are left as they are.
	 */
	public long getTime() {
		Clock c = CLOCKS.get();
		long now = System.nanoTime() / 1000000L - c.lost;
		if (c.last != Long.MIN_VALUE) {
			long step = now - c.last;
			if (step > 1000 && step <= 10000) {
				if (c.slow != Long.MIN_VALUE && c.last - c.slow < 5000) {
					c.lost += step - 900;
					now = c.last + 900;
				}
				c.slow = now;
			}
		}
		c.last = now;
		return now;
	}

	public void alert(String title, String message) {
		LWJGLUtil.log("Alert: " + title + ": " + message);
		nAlert(title, message);
	}

	public boolean openURL(String url) {
		return nOpenURL(url);
	}

	public String getClipboard() {
		return nGetClipboard();
	}

	private static native void nAlert(String title, String message);

	private static native boolean nOpenURL(String url);

	private static native String nGetClipboard();
}
