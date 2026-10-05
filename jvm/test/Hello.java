// The first Java program on iOS 6: what runs it, a loop for the JIT, garbage collection, threads, a hash map.
//   kostka:java?main=Hello
import java.util.HashMap;
import java.util.Map;

public class Hello {
    static long work(int n) {
        long sum = 0;
        for (int i = 0; i < n; i++) sum += (i * 31L) ^ (i >>> 3);
        return sum;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("Hello from Java " + System.getProperty("java.version") + " (" + System.getProperty("java.vm.name")
                + " " + System.getProperty("java.vm.version") + ") on " + System.getProperty("os.name") + " "
                + System.getProperty("os.version") + " " + System.getProperty("os.arch"));
        System.out.println("java.home " + System.getProperty("java.home"));
        Runtime rt = Runtime.getRuntime();
        System.out.println("processors " + rt.availableProcessors() + ", max memory " + rt.maxMemory() / 1048576 + " MB");

        // the same work a few times: the interpreter first, then compiled by C1
        for (int round = 1; round <= 5; round++) {
            long t0 = System.nanoTime();
            long r = work(10000000);
            System.out.println("round " + round + ": " + (System.nanoTime() - t0) / 1000000 + " ms (" + r + ")");
        }

        // garbage
        long t0 = System.nanoTime();
        long kept = 0;
        for (int i = 0; i < 200; i++) {
            byte[] b = new byte[1 << 20];
            b[i] = (byte) i;
            kept += b.length;
        }
        System.out.println("allocated " + kept / 1048576 + " MB in " + (System.nanoTime() - t0) / 1000000 + " ms, free "
                + rt.freeMemory() / 1048576 + " of " + rt.totalMemory() / 1048576 + " MB");

        // threads
        final long[] results = new long[4];
        Thread[] threads = new Thread[4];
        for (int i = 0; i < threads.length; i++) {
            final int k = i;
            threads[i] = new Thread(new Runnable() {
                public void run() { results[k] = work(2000000 + k); }
            });
            threads[i].start();
        }
        for (Thread t : threads) t.join();
        System.out.println("threads: " + results[0] + " " + results[3]);

        Map<String, Integer> map = new HashMap<String, Integer>();
        for (int i = 0; i < 10000; i++) map.put("key" + i, i);
        System.out.println("map: " + map.size() + " entries, key5000 -> " + map.get("key5000"));
        System.out.println(String.format("format: %.3f %s", Math.PI, "ok"));
        System.out.println("Goodbye from Java");
    }
}
