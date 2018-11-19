
import java.lang.*;

public class ThreadRunnable implements Runnable {

  private String name;
  private int time;

  public ThreadRunnable (String name, int time) {
    this.name = name;
    this.time = time;
    // Thread t1 = new Thread(this);
    // t1.start();
  }

  public void run () {
    System.out.println(name + " foi iniciada!");

    try {
      for (int i = 1; i < 7; i++) {
        System.out.println(name + ", tem contador valor: " + i);
        Thread.sleep(time);
      }
    } catch (InterruptedException e) {
      System.out.println(name + " foi interrompida...");
    }

    System.out.println(name + " foi finalizada!");
  }
}
