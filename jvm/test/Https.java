// Java's own HTTPS on iOS 6: the security providers, elliptic curves (the key exchange today's servers ask for), and
// connections to Mojang's servers (the game talks to them itself: profiles, skins, joining a server).
//   kostka:java?main=Https[&args=https://example.com/,debug]   (debug: the TLS handshake into java.log)
import java.io.InputStream;
import java.net.URL;
import java.security.KeyPairGenerator;
import java.security.Provider;
import java.security.Security;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import javax.crypto.KeyAgreement;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;

public class Https {
    public static void main(String[] args) throws Exception {
        List<String> urls = new ArrayList<String>();
        for (String a : args) {
            if (a.equals("debug")) System.setProperty("javax.net.debug", "ssl:handshake");
            else urls.add(a);
        }
        if (urls.isEmpty()) {
            urls.add("https://sessionserver.mojang.com/session/minecraft/profile/00000000000000000000000000000000");
            urls.add("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json");
        }
        for (Provider p : Security.getProviders()) System.out.println("provider " + p.getName() + " " + p.getVersion());
        try {
            KeyAgreement.getInstance("ECDH");
            System.out.println("ECDH: yes");
        } catch (Exception e) {
            System.out.println("ECDH: " + e);
        }
        try {
            KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
            g.initialize(256);
            g.generateKeyPair();
            System.out.println("EC key pair (P-256): yes");
        } catch (Exception e) {
            System.out.println("EC key pair: " + e);
        }
        SSLParameters params = SSLContext.getDefault().getDefaultSSLParameters();
        int ecdhe = 0;
        for (String s : params.getCipherSuites()) if (s.contains("_ECDHE_")) ecdhe++;
        System.out.println("cipher suites " + params.getCipherSuites().length + " (ECDHE " + ecdhe + "), protocols "
                + Arrays.toString(params.getProtocols()));
        for (String u : urls) {
            long t0 = System.nanoTime();
            try {
                HttpsURLConnection c = (HttpsURLConnection) new URL(u).openConnection();
                c.setConnectTimeout(15000);
                c.setReadTimeout(15000);
                int code = c.getResponseCode();
                String suite = c.getCipherSuite();
                InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
                int n = 0;
                if (in != null) {
                    byte[] b = new byte[8192];
                    for (int r; (r = in.read(b)) > 0; ) n += r;
                    in.close();
                }
                System.out.println(u + ": " + code + ", " + n + " bytes, " + suite + ", "
                        + (System.nanoTime() - t0) / 1000000 + " ms");
            } catch (Exception e) {
                System.out.println(u + ": " + e);
                for (Throwable t = e.getCause(); t != null; t = t.getCause()) System.out.println("  caused by " + t);
            }
        }
    }
}
