
public class TestMain  {
    public static void main (String args[]) {
      ThreadRunnableInterface thread1 = new ThreadRunnableInterface("Thread #1", 500);
      ThreadRunnableInterface thread2 = new ThreadRunnableInterface("Thread #2", 10);
      //Thread t1 = new Thread(thread1);
      //t1.start();
    }
}
