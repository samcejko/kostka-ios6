import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;

/**
 * Kostka: installs OptiFine from its installer - the jar the player downloaded from optifine.net - into Kostka's
 * Minecraft folder, as the installer's Install button does on a computer, without its window:
 *
 *   OptiFineInstall <installer.jar> <folder>
 *
 * The folder is laid out as the official launcher's (versions/, libraries/); the vanilla version must be there. The
 * installer makes a version of its own ("1.12.2-OptiFine_HD_U_G5", inheriting from 1.12.2) and its libraries, and puts
 * a profile into launcher_profiles.json, which it wants to find: an empty one is written first. Prints the new
 * version's name on the last line ("installed <id>"); when the installer fails, its exception ends main (Kostka
 * then gets 1 as the code).
 */
public class OptiFineInstall {
	public static void main(String[] args) throws Throwable {
		if (args.length < 2) throw new IllegalArgumentException("usage: OptiFineInstall <installer.jar> <folder>");
		File installer = new File(args[0]), dir = new File(args[1]);
		File profiles = new File(dir, "launcher_profiles.json");
		if (!profiles.exists()) {
			Writer w = new OutputStreamWriter(new FileOutputStream(profiles), "UTF-8");
			w.write("{\"profiles\":{}}\n");
			w.close();
		}
		String[] before = new File(dir, "versions").list();
		URLClassLoader loader = new URLClassLoader(new URL[] { installer.toURI().toURL() },
			OptiFineInstall.class.getClassLoader());
		try {
			Class<?> c = loader.loadClass("optifine.Installer");
			Method install = c.getMethod("doInstall", File.class);
			install.invoke(null, dir);
		} catch (InvocationTargetException e) {
			throw e.getCause();
		}
		// (the new version: the folder that was not there before, or the one named after the installer's edition)
		String made = null;
		java.util.Set<String> old = new java.util.HashSet<String>(java.util.Arrays.asList(before != null ? before : new String[0]));
		String[] after = new File(dir, "versions").list();
		for (String v : after != null ? after : new String[0])
			if (!old.contains(v) && v.contains("OptiFine")) made = v;
		if (made == null) {
			String name = installer.getName().replace(".jar", "");   // OptiFine_1.12.2_HD_U_G5
			int at = name.indexOf('_', "OptiFine_".length());
			if (at > 0) made = name.substring("OptiFine_".length(), at) + "-OptiFine" + name.substring(at);
		}
		System.out.println("installed " + made);
	}
}
