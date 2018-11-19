
public class TestMain {

  public static void main (String args[]) {

    ThreadRunnable thread1 = new ThreadRunnable("Thread #1", 100);
    ThreadRunnable thread2 = new ThreadRunnable("Thread #2", 500);
    ThreadRunnable thread3 = new ThreadRunnable("Thread #3", 900);

    Thread t1 = new Thread(thread1);
    Thread t2 = new Thread(thread2);
    Thread t3 = new Thread(thread3);

    t1.start();
    t2.start();
    t3.start();

    // UGLY SOLUTION
    // while (t1.isAlive() || t2.isAlive() || t3.isAlive()) {
    //   try {
    //     Thread.sleep(200);
    //   } catch (InterruptedException e) {
    //     e.printStackTrace();
    //   }
    // }

    try {
      t1.join();
      t2.join();
      t3.join();
    } catch (InterruptedException e) {
      e.printStackTrace();
    }

    System.out.println("PROGRAMA FINALIZADO!");
  }
}
