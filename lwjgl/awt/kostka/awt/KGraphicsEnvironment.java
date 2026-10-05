/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.DisplayMode;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.GraphicsConfiguration;
import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Rectangle;
import java.awt.Transparency;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.awt.image.ColorModel;
import java.awt.image.DirectColorModel;
import java.util.Locale;

/**
 * Kostka's AWT: one screen, the iPad's, and drawing on pictures (BufferedImage.createGraphics) done by KGraphics in
 * Java. No fonts: text is not drawn.
 */
public class KGraphicsEnvironment extends GraphicsEnvironment {
	private final Screen screen = new Screen();

	public GraphicsDevice[] getScreenDevices() {
		return new GraphicsDevice[] { screen };
	}

	public GraphicsDevice getDefaultScreenDevice() {
		return screen;
	}

	public Graphics2D createGraphics(BufferedImage img) {
		return new KGraphics(img);
	}

	public Font[] getAllFonts() {
		return new Font[0];
	}

	public String[] getAvailableFontFamilyNames() {
		return new String[] { Font.DIALOG, Font.SANS_SERIF, Font.SERIF, Font.MONOSPACED };
	}

	public String[] getAvailableFontFamilyNames(Locale l) {
		return getAvailableFontFamilyNames();
	}

	static final class Screen extends GraphicsDevice {
		private final Configuration configuration = new Configuration(this);

		public int getType() {
			return TYPE_RASTER_SCREEN;
		}

		public String getIDstring() {
			return "iOS";
		}

		public GraphicsConfiguration[] getConfigurations() {
			return new GraphicsConfiguration[] { configuration };
		}

		public GraphicsConfiguration getDefaultConfiguration() {
			return configuration;
		}

		public DisplayMode getDisplayMode() {
			return new DisplayMode(KToolkit.screenWidth(), KToolkit.screenHeight(), 32, 60);
		}

		public DisplayMode[] getDisplayModes() {
			return new DisplayMode[] { getDisplayMode() };
		}
	}

	static final class Configuration extends GraphicsConfiguration {
		private final Screen screen;

		Configuration(Screen screen) {
			this.screen = screen;
		}

		public GraphicsDevice getDevice() {
			return screen;
		}

		public ColorModel getColorModel() {
			return new DirectColorModel(24, 0xff0000, 0xff00, 0xff);
		}

		public ColorModel getColorModel(int transparency) {
			return transparency == Transparency.OPAQUE ? getColorModel() : ColorModel.getRGBdefault();
		}

		public AffineTransform getDefaultTransform() {
			return new AffineTransform();
		}

		public AffineTransform getNormalizingTransform() {
			return new AffineTransform();
		}

		public Rectangle getBounds() {
			return new Rectangle(0, 0, KToolkit.screenWidth(), KToolkit.screenHeight());
		}
	}
}
