// System.exit with a code, after the line of an exception: how Kostka ends a program that stops with an error (an
// alert with the reason, then the app closes) or without one (the app closes at once).
//   kostka:java?main=Exit&args=3
public class Exit {
    public static void main(String[] args) {
        int code = args.length > 0 ? Integer.parseInt(args[0]) : 1;
        if (code != 0) System.err.println("java.lang.IllegalStateException: a test of the end with the code " + code);
        System.exit(code);
    }
}
