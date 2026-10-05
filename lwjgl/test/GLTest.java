import org.lwjgl.LWJGLException;
import org.lwjgl.Sys;
import org.lwjgl.input.Keyboard;
import org.lwjgl.input.Mouse;
import org.lwjgl.opengl.ContextCapabilities;
import org.lwjgl.opengl.Display;
import org.lwjgl.opengl.DisplayMode;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GLContext;

/**
 * Kostka's first test of LWJGL on iOS: a window, desktop OpenGL 1.x through gl4es (a turning triangle in
 * immediate mode, a square under the finger), touches as the mouse, the on-screen keys. Esc ends it; it ends
 * by itself after two minutes. Writes what it sees (and the frame rate) to java.log.
 */
public class GLTest {
	public static void main(String[] args) throws LWJGLException {
		System.out.println("LWJGL " + Sys.getVersion() + " on " + System.getProperty("os.name") + " " + System.getProperty("os.version"));
		Display.setDisplayMode(new DisplayMode(854, 480));
		Display.setTitle("Kostka GL test");
		Display.create();
		System.out.println("GL_VENDOR " + GL11.glGetString(GL11.GL_VENDOR));
		System.out.println("GL_RENDERER " + GL11.glGetString(GL11.GL_RENDERER));
		System.out.println("GL_VERSION " + GL11.glGetString(GL11.GL_VERSION));
		String ext = GL11.glGetString(GL11.GL_EXTENSIONS);
		System.out.println("GL_EXTENSIONS " + (ext == null ? 0 : ext.split(" ").length));
		ContextCapabilities caps = GLContext.getCapabilities();
		System.out.println("OpenGL 1.5 " + caps.OpenGL15 + ", 2.0 " + caps.OpenGL20 + ", 2.1 " + caps.OpenGL21
			+ ", FBO " + (caps.GL_EXT_framebuffer_object || caps.GL_ARB_framebuffer_object)
			+ ", VBO " + caps.GL_ARB_vertex_buffer_object);
		System.out.println("display " + Display.getWidth() + "x" + Display.getHeight());

		long start = System.currentTimeMillis(), report = start;
		int frames = 0;
		float angle = 0;
		boolean grabbed = false;
		boolean done = false;
		while (!done && !Display.isCloseRequested() && System.currentTimeMillis() - start < 120000) {
			int w = Display.getWidth(), h = Display.getHeight();
			GL11.glViewport(0, 0, w, h);
			GL11.glClearColor(0.1f, 0.15f, 0.3f, 1);
			GL11.glClear(GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT);
			GL11.glMatrixMode(GL11.GL_PROJECTION);
			GL11.glLoadIdentity();
			GL11.glOrtho(0, w, 0, h, -1, 1);
			GL11.glMatrixMode(GL11.GL_MODELVIEW);
			GL11.glLoadIdentity();

			GL11.glPushMatrix();
			GL11.glTranslatef(w / 2f, h / 2f, 0);
			GL11.glRotatef(angle, 0, 0, 1);
			float r = h * 0.35f;
			GL11.glBegin(GL11.GL_TRIANGLES);
			GL11.glColor3f(1, 0.2f, 0.2f);
			GL11.glVertex2f(0, r);
			GL11.glColor3f(0.2f, 1, 0.2f);
			GL11.glVertex2f(-r * 0.87f, -r * 0.5f);
			GL11.glColor3f(0.3f, 0.4f, 1);
			GL11.glVertex2f(r * 0.87f, -r * 0.5f);
			GL11.glEnd();
			GL11.glPopMatrix();

			// the mouse: a square at its place, red while the left button is down
			int mx = Mouse.getX(), my = Mouse.getY();
			if (Mouse.isButtonDown(0))
				GL11.glColor3f(1, 0.3f, 0.3f);
			else
				GL11.glColor3f(1, 1, 1);
			GL11.glBegin(GL11.GL_QUADS);
			GL11.glVertex2f(mx - 12, my - 12);
			GL11.glVertex2f(mx + 12, my - 12);
			GL11.glVertex2f(mx + 12, my + 12);
			GL11.glVertex2f(mx - 12, my + 12);
			GL11.glEnd();

			Display.update();
			angle += 1.5f;
			frames++;

			while (Mouse.next()) {
				if (Mouse.getEventButton() >= 0)
					System.out.println("mouse " + Mouse.getEventButton() + (Mouse.getEventButtonState() ? " down" : " up")
						+ " at " + Mouse.getEventX() + "," + Mouse.getEventY());
			}
			while (Keyboard.next()) {
				int key = Keyboard.getEventKey();
				boolean down = Keyboard.getEventKeyState();
				System.out.println("key " + Keyboard.getKeyName(key) + (down ? " down" : " up") + " '" + Keyboard.getEventCharacter() + "'");
				if (down && key == Keyboard.KEY_ESCAPE)
					done = true;
				// G grabs the mouse (the game's look-around mode, with the on-screen controls)
				if (down && key == Keyboard.KEY_G) {
					grabbed = !grabbed;
					Mouse.setGrabbed(grabbed);
				}
			}
			long now = System.currentTimeMillis();
			if (now - report >= 5000) {
				System.out.println(String.format("%.1f fps", frames * 1000.0 / (now - report)));
				frames = 0;
				report = now;
			}
		}
		Display.destroy();
		System.out.println("GL test done");
	}
}
