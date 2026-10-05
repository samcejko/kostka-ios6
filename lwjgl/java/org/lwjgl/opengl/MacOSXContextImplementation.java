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

import java.nio.ByteBuffer;
import java.nio.IntBuffer;

import org.lwjgl.LWJGLException;

/**
 * Kostka: an OpenGL context on iOS: an EAGL (OpenGL ES 2.0) context that draws into a framebuffer object on
 * the window's layer, with gl4es translating the game's desktop OpenGL (ios_context.m). Keeps the name of the
 * Mac OS X class it replaces.
 */
final class MacOSXContextImplementation implements ContextImplementation {

	public ByteBuffer create(PeerInfo peer_info, IntBuffer attribs, ByteBuffer shared_context_handle) throws LWJGLException {
		ByteBuffer peer_handle = peer_info.lockAndGetHandle();
		try {
			return nCreate(peer_handle, shared_context_handle);
		} finally {
			peer_info.unlock();
		}
	}

	private static native ByteBuffer nCreate(ByteBuffer peer_handle, ByteBuffer shared_context_handle) throws LWJGLException;

	public void swapBuffers() throws LWJGLException {
		ContextGL current_context = ContextGL.getCurrentContext();
		if ( current_context == null )
			throw new IllegalStateException("No context is current");
		synchronized ( current_context ) {
			nSwapBuffers(current_context.getHandle());
		}
	}

	private static native void nSwapBuffers(ByteBuffer context_handle) throws LWJGLException;

	/** (OpenCL sharing: none on iOS) */
	long getCGLShareGroup(ByteBuffer context_handle) {
		return 0;
	}

	public void update(ByteBuffer context_handle) {
	}

	public void releaseCurrentContext() throws LWJGLException {
		nReleaseCurrentContext();
	}

	private static native void nReleaseCurrentContext() throws LWJGLException;

	public void releaseDrawable(ByteBuffer context_handle) throws LWJGLException {
	}

	public void makeCurrent(PeerInfo peer_info, ByteBuffer handle) throws LWJGLException {
		ByteBuffer peer_handle = peer_info.lockAndGetHandle();
		try {
			nMakeCurrent(handle, MacOSXDisplay.getWindowHandle());
		} finally {
			peer_info.unlock();
		}
	}

	private static native void nMakeCurrent(ByteBuffer context_handle, ByteBuffer window_handle) throws LWJGLException;

	public boolean isCurrent(ByteBuffer handle) throws LWJGLException {
		return nIsCurrent(handle);
	}

	private static native boolean nIsCurrent(ByteBuffer context_handle) throws LWJGLException;

	public void setSwapInterval(int value) {
		// (EAGL always waits for the display)
	}

	public void destroy(PeerInfo peer_info, ByteBuffer handle) throws LWJGLException {
		nDestroy(handle);
	}

	private static native void nDestroy(ByteBuffer context_handle) throws LWJGLException;
}
