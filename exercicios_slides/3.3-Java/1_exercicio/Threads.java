
import java.lang.*;

public class Threads extends Thread{

  private String name;
  private int time;

  // constructor da minha classe thread
  public Threads (String name, int time) {
    this.name = name;
    this.time = time;
    start();
  }

  // executa o código que quero paralelizar
  public void run () {
    System.out.println(name + " foi iniciada!");

    try {

      for (int i = 0; i < 7; i++) {
        System.out.println(name + ", tem contador valor: " + i);
        Thread.sleep(time);
      }

    }catch (InterruptedException e) {
      System.out.println(name + " foi interrompida");
    }

    System.out.println(name + " foi terminada!");
  }


}
