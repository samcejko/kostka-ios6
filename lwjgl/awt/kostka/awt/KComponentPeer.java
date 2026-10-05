/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.AWTEvent;
import java.awt.AWTException;
import java.awt.BufferCapabilities;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.GraphicsConfiguration;
import java.awt.GraphicsEnvironment;
import java.awt.Image;
import java.awt.Insets;
import java.awt.Point;
import java.awt.Rectangle;
import java.awt.event.PaintEvent;
import java.awt.image.BufferedImage;
import java.awt.image.ColorModel;
import java.awt.image.ImageObserver;
import java.awt.image.ImageProducer;
import java.awt.image.VolatileImage;
import java.awt.peer.CanvasPeer;
import java.awt.peer.ComponentPeer;
import java.awt.peer.ContainerPeer;
import java.awt.peer.PanelPeer;

import sun.awt.CausedFocusEvent;
import sun.java2d.pipe.Region;

/**
 * Kostka's AWT: the peer of a component that exists without being drawn (a canvas, a panel, an applet; KWindowPeer
 * extends it for the windows). It keeps the bounds AWT gives it; it paints nothing.
 */
public class KComponentPeer implements CanvasPeer, PanelPeer {
	protected final Component target;
	protected final Rectangle bounds = new Rectangle();
	protected boolean visible;

	KComponentPeer(Component target) {
		this.target = target;
		bounds.setBounds(target.getBounds());
	}

	static GraphicsConfiguration screen() {
		return GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice().getDefaultConfiguration();
	}

	public boolean isObscured() {
		return false;
	}

	public boolean canDetermineObscurity() {
		return false;
	}

	public void setVisible(boolean v) {
		visible = v;
	}

	public void setEnabled(boolean e) {
	}

	public void paint(Graphics g) {
	}

	public void print(Graphics g) {
	}

	public void setBounds(int x, int y, int width, int height, int op) {
		bounds.setBounds(x, y, width, height);
	}

	public void handleEvent(AWTEvent e) {
	}

	public void coalescePaintEvent(PaintEvent e) {
	}

	public Point getLocationOnScreen() {
		Point p = new Point(bounds.x, bounds.y);
		Component parent = target.getParent();
		if (parent != null && parent.isShowing()) {
			Point q = parent.getLocationOnScreen();
			p.translate(q.x, q.y);
		}
		return p;
	}

	public Dimension getPreferredSize() {
		return new Dimension(bounds.width, bounds.height);
	}

	public Dimension getMinimumSize() {
		return new Dimension(1, 1);
	}

	public ColorModel getColorModel() {
		return ColorModel.getRGBdefault();
	}

	public Graphics getGraphics() {
		// (nothing of AWT reaches the screen: a picture the size of the component takes what is drawn)
		int w = Math.max(1, bounds.width), h = Math.max(1, bounds.height);
		return new KGraphics(new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB));
	}

	public FontMetrics getFontMetrics(Font font) {
		return new FontMetrics(font) {
			private static final long serialVersionUID = 1L;
		};
	}

	public void dispose() {
	}

	public void setForeground(Color c) {
	}

	public void setBackground(Color c) {
	}

	public void setFont(Font f) {
	}

	public void updateCursorImmediately() {
	}

	public boolean requestFocus(Component lightweightChild, boolean temporary, boolean focusedWindowChangeAllowed,
			long time, CausedFocusEvent.Cause cause) {
		return false;
	}

	public boolean isFocusable() {
		return true;
	}

	public Image createImage(ImageProducer producer) {
		return null;
	}

	public Image createImage(int width, int height) {
		return new BufferedImage(Math.max(1, width), Math.max(1, height), BufferedImage.TYPE_INT_RGB);
	}

	public VolatileImage createVolatileImage(int width, int height) {
		return null;
	}

	public boolean prepareImage(Image img, int w, int h, ImageObserver o) {
		return true;
	}

	public int checkImage(Image img, int w, int h, ImageObserver o) {
		return ImageObserver.ALLBITS;
	}

	public GraphicsConfiguration getGraphicsConfiguration() {
		return screen();
	}

	public boolean handlesWheelScrolling() {
		return false;
	}

	public void createBuffers(int numBuffers, BufferCapabilities caps) throws AWTException {
		throw new AWTException("No buffers on iOS");
	}

	public Image getBackBuffer() {
		return null;
	}

	public void flip(int x1, int y1, int x2, int y2, BufferCapabilities.FlipContents flipAction) {
	}

	public void destroyBuffers() {
	}

	public void reparent(ContainerPeer newContainer) {
	}

	public boolean isReparentSupported() {
		return false;
	}

	public void layout() {
	}

	public void applyShape(Region shape) {
	}

	public void setZOrder(ComponentPeer above) {
	}

	public boolean updateGraphicsData(GraphicsConfiguration gc) {
		return false;
	}

	/* CanvasPeer */

	public GraphicsConfiguration getAppropriateGraphicsConfiguration(GraphicsConfiguration gc) {
		return gc;
	}

	/* ContainerPeer */

	public Insets getInsets() {
		return new Insets(0, 0, 0, 0);
	}

	public void beginValidate() {
	}

	public void endValidate() {
	}

	public void beginLayout() {
	}

	public void endLayout() {
	}
}
