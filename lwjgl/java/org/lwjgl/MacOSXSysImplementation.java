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

	public long getTime() {
		// (a monotonic clock: games time their frames with it)
		return System.nanoTime() / 1000000L;
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
