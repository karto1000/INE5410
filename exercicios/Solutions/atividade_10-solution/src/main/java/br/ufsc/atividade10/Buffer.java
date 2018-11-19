package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;

import static br.ufsc.atividade10.Piece.Type.*;

public class Buffer {
    private final int maxSize;
    private int nX = 0;
    private int nO = 0;
    private LinkedList<Piece> queue = new LinkedList<>();

    public Buffer() {
        this(10);
    }
    public Buffer(int maxSize) {
        this.maxSize = maxSize;
    }

    public synchronized void add(Piece piece) throws InterruptedException {
        Piece.Type t = piece.getType();
        int maxO = maxSize - 1;
        int maxX = maxSize - 2;
        while (queue.size() >= maxSize || (t == O && nO >= maxO) || (t == X && nX >= maxX))
            wait();
        queue.add(piece);
        if (t == X) ++nX;
        if (t == O) ++nO;
        notifyAll();
    }

    public synchronized void takeOXO(@Nonnull List<Piece> xList,
                                     @Nonnull List<Piece> oList) throws InterruptedException {
        while (nX < 1 || nO < 2)
            wait();

        Iterator<Piece> it = queue.iterator();
        while (it.hasNext() && (xList.size() < 1 || oList.size() < 2)) {
            Piece piece = it.next();
            if (piece.getType() == X && xList.size() < 1) {
                xList.add(piece);
                it.remove();
                --nX;
            } else if (piece.getType() == O && oList.size() < 2) {
                oList.add(piece);
                it.remove();
                --nO;
            }
        }
        notifyAll();

        assert xList.size() == 1;
        assert oList.size() == 2;
    }
}
