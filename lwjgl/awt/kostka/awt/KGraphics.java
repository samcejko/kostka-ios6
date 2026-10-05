/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Composite;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.GraphicsConfiguration;
import java.awt.GraphicsEnvironment;
import java.awt.Image;
import java.awt.Paint;
import java.awt.Polygon;
import java.awt.Rectangle;
import java.awt.RenderingHints;
import java.awt.Shape;
import java.awt.Stroke;
import java.awt.font.FontRenderContext;
import java.awt.font.GlyphVector;
import java.awt.geom.AffineTransform;
import java.awt.geom.Arc2D;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Line2D;
import java.awt.geom.NoninvertibleTransformException;
import java.awt.geom.PathIterator;
import java.awt.geom.Rectangle2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.awt.image.BufferedImageOp;
import java.awt.image.ImageObserver;
import java.awt.image.RenderedImage;
import java.awt.image.renderable.RenderableImage;
import java.text.AttributedCharacterIterator;
import java.util.Map;

/**
 * Kostka's AWT: drawing on a BufferedImage in plain Java - Java2D's own drawing is native code iOS does not have.
 * Shapes are filled and outlined one pixel wide, pictures are copied and scaled (nearest pixel, any affine
 * transform), with source-over or source compositing. Text is not drawn (there are no fonts). Enough for what games
 * draw on their textures: skins put together, missing-texture patterns, thumbnails.
 */
public class KGraphics extends Graphics2D {
	private final BufferedImage image;
	private AffineTransform transform;
	private Rectangle clip;   // in the image's pixels, or null
	private Color color = Color.WHITE;
	private Color background = Color.BLACK;
	private Composite composite = AlphaComposite.SrcOver;
	private Stroke stroke = new BasicStroke();
	private Font font = new Font(Font.DIALOG, Font.PLAIN, 12);
	private final RenderingHints hints = new RenderingHints(null);

	public KGraphics(BufferedImage image) {
		this.image = image;
		this.transform = new AffineTransform();
	}

	private KGraphics(KGraphics g) {
		image = g.image;
		transform = new AffineTransform(g.transform);
		clip = g.clip == null ? null : new Rectangle(g.clip);
		color = g.color;
		background = g.background;
		composite = g.composite;
		stroke = g.stroke;
		font = g.font;
		hints.putAll(g.hints);
	}

	public Graphics create() {
		return new KGraphics(this);
	}

	public void dispose() {
	}

	/* Pixels */

	private Rectangle area() {
		Rectangle r = new Rectangle(0, 0, image.getWidth(), image.getHeight());
		return clip == null ? r : r.intersection(clip);
	}

	private float extraAlpha() {
		return composite instanceof AlphaComposite ? ((AlphaComposite)composite).getAlpha() : 1f;
	}

	private boolean sourceOnly() {
		return composite instanceof AlphaComposite && ((AlphaComposite)composite).getRule() == AlphaComposite.SRC;
	}

	private void put(int x, int y, int argb) {
		float a = ((argb >>> 24) / 255f) * extraAlpha();
		if (sourceOnly()) {
			image.setRGB(x, y, ((int)(a * 255 + 0.5f) << 24) | (argb & 0xffffff));
			return;
		}
		if (a >= 0.999f) {
			image.setRGB(x, y, argb | 0xff000000);
			return;
		}
		if (a <= 0.001f)
			return;
		int d = image.getRGB(x, y);
		float da = (d >>> 24) / 255f, oa = a + da * (1 - a);
		int r = blend((argb >> 16) & 0xff, (d >> 16) & 0xff, a, da, oa);
		int g = blend((argb >> 8) & 0xff, (d >> 8) & 0xff, a, da, oa);
		int b = blend(argb & 0xff, d & 0xff, a, da, oa);
		image.setRGB(x, y, ((int)(oa * 255 + 0.5f) << 24) | (r << 16) | (g << 8) | b);
	}

	private static int blend(int s, int d, float sa, float da, float oa) {
		if (oa <= 0)
			return 0;
		return Math.min(255, (int)((s * sa + d * da * (1 - sa)) / oa + 0.5f));
	}

	/** Fills a shape given in the image's pixels */
	private void fillDevice(Shape s, int argb) {
		Rectangle b = s.getBounds().intersection(area());
		if (b.isEmpty())
			return;
		boolean rect = s instanceof Rectangle2D;
		for (int y = b.y; y < b.y + b.height; y++)
			for (int x = b.x; x < b.x + b.width; x++)
				if (rect || s.contains(x + 0.5, y + 0.5))
					put(x, y, argb);
	}

	private void lineDevice(int x0, int y0, int x1, int y1, int argb) {
		Rectangle a = area();
		int dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, e = dx + dy;
		while (true) {
			if (a.contains(x0, y0))
				put(x0, y0, argb);
			if (x0 == x1 && y0 == y1)
				break;
			int e2 = 2 * e;
			if (e2 >= dy) { e += dy; x0 += sx; }
			if (e2 <= dx) { e += dx; y0 += sy; }
		}
	}

	public void fill(Shape s) {
		fillDevice(transform.createTransformedShape(s), color.getRGB());
	}

	public void draw(Shape s) {
		PathIterator it = s.getPathIterator(transform, 0.5);
		double[] c = new double[6];
		double sx = 0, sy = 0, lx = 0, ly = 0;
		int argb = color.getRGB();
		while (!it.isDone()) {
			int type = it.currentSegment(c);
			if (type == PathIterator.SEG_MOVETO) {
				sx = lx = c[0];
				sy = ly = c[1];
			} else if (type == PathIterator.SEG_LINETO) {
				lineDevice((int)Math.floor(lx), (int)Math.floor(ly), (int)Math.floor(c[0]), (int)Math.floor(c[1]), argb);
				lx = c[0];
				ly = c[1];
			} else if (type == PathIterator.SEG_CLOSE) {
				lineDevice((int)Math.floor(lx), (int)Math.floor(ly), (int)Math.floor(sx), (int)Math.floor(sy), argb);
				lx = sx;
				ly = sy;
			}
			it.next();
		}
	}

	public void fillRect(int x, int y, int width, int height) {
		if (width > 0 && height > 0)
			fill(new Rectangle(x, y, width, height));
	}

	public void clearRect(int x, int y, int width, int height) {
		Composite old = composite;
		composite = AlphaComposite.Src;
		fillDevice(transform.createTransformedShape(new Rectangle(x, y, width, height)), background.getRGB());
		composite = old;
	}

	public void drawLine(int x1, int y1, int x2, int y2) {
		draw(new Line2D.Float(x1, y1, x2, y2));
	}

	public void drawRoundRect(int x, int y, int width, int height, int arcWidth, int arcHeight) {
		draw(new RoundRectangle2D.Float(x, y, width, height, arcWidth, arcHeight));
	}

	public void fillRoundRect(int x, int y, int width, int height, int arcWidth, int arcHeight) {
		fill(new RoundRectangle2D.Float(x, y, width, height, arcWidth, arcHeight));
	}

	public void drawOval(int x, int y, int width, int height) {
		draw(new Ellipse2D.Float(x, y, width, height));
	}

	public void fillOval(int x, int y, int width, int height) {
		fill(new Ellipse2D.Float(x, y, width, height));
	}

	public void drawArc(int x, int y, int width, int height, int startAngle, int arcAngle) {
		draw(new Arc2D.Float(x, y, width, height, startAngle, arcAngle, Arc2D.OPEN));
	}

	public void fillArc(int x, int y, int width, int height, int startAngle, int arcAngle) {
		fill(new Arc2D.Float(x, y, width, height, startAngle, arcAngle, Arc2D.PIE));
	}

	public void drawPolyline(int[] xPoints, int[] yPoints, int nPoints) {
		for (int i = 1; i < nPoints; i++)
			drawLine(xPoints[i - 1], yPoints[i - 1], xPoints[i], yPoints[i]);
	}

	public void drawPolygon(int[] xPoints, int[] yPoints, int nPoints) {
		draw(new Polygon(xPoints, yPoints, nPoints));
	}

	public void fillPolygon(int[] xPoints, int[] yPoints, int nPoints) {
		fill(new Polygon(xPoints, yPoints, nPoints));
	}

	public void copyArea(int x, int y, int width, int height, int dx, int dy) {
		Point2 p = device(x, y);
		int w = Math.max(0, width), h = Math.max(0, height);
		int[] px = new int[w * h];
		Rectangle src = new Rectangle(p.x, p.y, w, h).intersection(new Rectangle(0, 0, image.getWidth(), image.getHeight()));
		if (src.isEmpty())
			return;
		image.getRGB(src.x, src.y, src.width, src.height, px, 0, src.width);
		Rectangle a = area();
		for (int j = 0; j < src.height; j++)
			for (int i = 0; i < src.width; i++)
				if (a.contains(src.x + i + dx, src.y + j + dy))
					image.setRGB(src.x + i + dx, src.y + j + dy, px[j * src.width + i]);
	}

	private static final class Point2 {
		final int x, y;
		Point2(int x, int y) { this.x = x; this.y = y; }
	}

	private Point2 device(int x, int y) {
		double[] p = { x, y };
		transform.transform(p, 0, p, 0, 1);
		return new Point2((int)Math.floor(p[0] + 0.5), (int)Math.floor(p[1] + 0.5));
	}

	/* Pictures */

	private static BufferedImage buffered(Image img) {
		return img instanceof BufferedImage ? (BufferedImage)img : null;
	}

	/** Draws src's [sx1,sx2) x [sy1,sy2) into the user rectangle [dx1,dx2) x [dy1,dy2) under `at` (nearest pixel) */
	private void picture(BufferedImage src, AffineTransform at, double dx1, double dy1, double dx2, double dy2,
			double sx1, double sy1, double sx2, double sy2, Color bg) {
		if (dx1 == dx2 || dy1 == dy2 || sx1 == sx2 || sy1 == sy2)
			return;
		double ux = Math.min(dx1, dx2), uy = Math.min(dy1, dy2), uw = Math.abs(dx2 - dx1), uh = Math.abs(dy2 - dy1);
		Rectangle b = at.createTransformedShape(new Rectangle2D.Double(ux, uy, uw, uh)).getBounds().intersection(area());
		if (b.isEmpty())
			return;
		double[] m = new double[6];
		try {
			at.createInverse().getMatrix(m);
		} catch (NoninvertibleTransformException e) {
			return;
		}
		int sw = src.getWidth(), sh = src.getHeight(), bgc = bg == null ? 0 : bg.getRGB();
		for (int y = b.y; y < b.y + b.height; y++) {
			for (int x = b.x; x < b.x + b.width; x++) {
				double px = x + 0.5, py = y + 0.5;
				double u = m[0] * px + m[2] * py + m[4], v = m[1] * px + m[3] * py + m[5];
				if (u < ux || u >= ux + uw || v < uy || v >= uy + uh)
					continue;
				int si = (int)Math.floor(sx1 + (u - dx1) / (dx2 - dx1) * (sx2 - sx1));
				int sj = (int)Math.floor(sy1 + (v - dy1) / (dy2 - dy1) * (sy2 - sy1));
				if (si < 0 || sj < 0 || si >= sw || sj >= sh)
					continue;
				int c = src.getRGB(si, sj);
				if (bg != null && (c >>> 24) != 0xff) {
					put(x, y, bgc);
				}
				put(x, y, c);
			}
		}
	}

	public boolean drawImage(Image img, int x, int y, ImageObserver observer) {
		return drawImage(img, x, y, null, observer);
	}

	public boolean drawImage(Image img, int x, int y, Color bgcolor, ImageObserver observer) {
		BufferedImage b = buffered(img);
		if (b != null)
			picture(b, transform, x, y, x + b.getWidth(), y + b.getHeight(), 0, 0, b.getWidth(), b.getHeight(), bgcolor);
		return true;
	}

	public boolean drawImage(Image img, int x, int y, int width, int height, ImageObserver observer) {
		return drawImage(img, x, y, width, height, null, observer);
	}

	public boolean drawImage(Image img, int x, int y, int width, int height, Color bgcolor, ImageObserver observer) {
		BufferedImage b = buffered(img);
		if (b != null)
			picture(b, transform, x, y, x + width, y + height, 0, 0, b.getWidth(), b.getHeight(), bgcolor);
		return true;
	}

	public boolean drawImage(Image img, int dx1, int dy1, int dx2, int dy2, int sx1, int sy1, int sx2, int sy2, ImageObserver observer) {
		return drawImage(img, dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2, null, observer);
	}

	public boolean drawImage(Image img, int dx1, int dy1, int dx2, int dy2, int sx1, int sy1, int sx2, int sy2, Color bgcolor,
			ImageObserver observer) {
		BufferedImage b = buffered(img);
		if (b != null)
			picture(b, transform, dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2, bgcolor);
		return true;
	}

	public boolean drawImage(Image img, AffineTransform xform, ImageObserver obs) {
		BufferedImage b = buffered(img);
		if (b != null) {
			AffineTransform at = new AffineTransform(transform);
			if (xform != null)
				at.concatenate(xform);
			picture(b, at, 0, 0, b.getWidth(), b.getHeight(), 0, 0, b.getWidth(), b.getHeight(), null);
		}
		return true;
	}

	public void drawImage(BufferedImage img, BufferedImageOp op, int x, int y) {
		drawImage(op == null ? img : op.filter(img, null), x, y, null);
	}

	public void drawRenderedImage(RenderedImage img, AffineTransform xform) {
		if (img instanceof BufferedImage)
			drawImage((BufferedImage)img, xform, null);
	}

	public void drawRenderableImage(RenderableImage img, AffineTransform xform) {
		drawRenderedImage(img.createDefaultRendering(), xform);
	}

	/* Text: no fonts on iOS */

	public void drawString(String str, int x, int y) {
	}

	public void drawString(String str, float x, float y) {
	}

	public void drawString(AttributedCharacterIterator iterator, int x, int y) {
	}

	public void drawString(AttributedCharacterIterator iterator, float x, float y) {
	}

	public void drawGlyphVector(GlyphVector g, float x, float y) {
	}

	public Font getFont() {
		return font;
	}

	public void setFont(Font font) {
		if (font != null)
			this.font = font;
	}

	public FontMetrics getFontMetrics(Font f) {
		return new FontMetrics(f) {
			private static final long serialVersionUID = 1L;
		};
	}

	public FontRenderContext getFontRenderContext() {
		return new FontRenderContext(new AffineTransform(transform), false, false);
	}

	/* State */

	public Color getColor() {
		return color;
	}

	public void setColor(Color c) {
		if (c != null)
			color = c;
	}

	public void setPaintMode() {
		composite = AlphaComposite.SrcOver;
	}

	public void setXORMode(Color c1) {
	}

	public Paint getPaint() {
		return color;
	}

	public void setPaint(Paint paint) {
		if (paint instanceof Color)
			color = (Color)paint;
	}

	public Composite getComposite() {
		return composite;
	}

	public void setComposite(Composite comp) {
		if (comp != null)
			composite = comp;
	}

	public void setBackground(Color c) {
		if (c != null)
			background = c;
	}

	public Color getBackground() {
		return background;
	}

	public Stroke getStroke() {
		return stroke;
	}

	public void setStroke(Stroke s) {
		if (s != null)
			stroke = s;
	}

	public void setRenderingHint(RenderingHints.Key hintKey, Object hintValue) {
		hints.put(hintKey, hintValue);
	}

	public Object getRenderingHint(RenderingHints.Key hintKey) {
		return hints.get(hintKey);
	}

	public void setRenderingHints(Map<?, ?> h) {
		hints.clear();
		hints.putAll(h);
	}

	public void addRenderingHints(Map<?, ?> h) {
		hints.putAll(h);
	}

	public RenderingHints getRenderingHints() {
		return (RenderingHints)hints.clone();
	}

	public GraphicsConfiguration getDeviceConfiguration() {
		return GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice().getDefaultConfiguration();
	}

	public boolean hit(Rectangle rect, Shape s, boolean onStroke) {
		return transform.createTransformedShape(s).intersects(rect);
	}

	/* Transform */

	public void translate(int x, int y) {
		transform.translate(x, y);
	}

	public void translate(double tx, double ty) {
		transform.translate(tx, ty);
	}

	public void rotate(double theta) {
		transform.rotate(theta);
	}

	public void rotate(double theta, double x, double y) {
		transform.rotate(theta, x, y);
	}

	public void scale(double sx, double sy) {
		transform.scale(sx, sy);
	}

	public void shear(double shx, double shy) {
		transform.shear(shx, shy);
	}

	public void transform(AffineTransform tx) {
		transform.concatenate(tx);
	}

	public void setTransform(AffineTransform tx) {
		transform = new AffineTransform(tx);
	}

	public AffineTransform getTransform() {
		return new AffineTransform(transform);
	}

	/* Clip: kept as a rectangle of the image's pixels */

	public Rectangle getClipBounds() {
		Shape c = getClip();
		return c == null ? null : c.getBounds();
	}

	public void clipRect(int x, int y, int width, int height) {
		clip(new Rectangle(x, y, width, height));
	}

	public void setClip(int x, int y, int width, int height) {
		setClip(new Rectangle(x, y, width, height));
	}

	public Shape getClip() {
		if (clip == null)
			return null;
		try {
			return transform.createInverse().createTransformedShape(clip);
		} catch (NoninvertibleTransformException e) {
			return null;
		}
	}

	public void setClip(Shape s) {
		clip = s == null ? null : transform.createTransformedShape(s).getBounds();
	}

	public void clip(Shape s) {
		Rectangle r = transform.createTransformedShape(s).getBounds();
		clip = clip == null ? r : clip.intersection(r);
	}
}
