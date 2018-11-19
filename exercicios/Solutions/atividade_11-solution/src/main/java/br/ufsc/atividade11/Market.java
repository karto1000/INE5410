package br.ufsc.atividade11;

import javax.annotation.Nonnull;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class Market {
    private Map<Product, Double> prices = new HashMap<>();
    private Map<Product, ReadWriteLock> locks = new HashMap<>();
    private Map<Product, Condition> offerConditions = new HashMap<>();

    public Market() {
        for (Product product : Product.values()) {
            prices.put(product, 1.99);
            ReentrantReadWriteLock rwLock = new ReentrantReadWriteLock();
            locks.put(product, rwLock);
            offerConditions.put(product, rwLock.writeLock().newCondition());
        }
    }

    public void setPrice(@Nonnull Product product, double value) {
        Lock wLock = locks.get(product).writeLock();
        wLock.lock();
        try {
            double old = prices.get(product);
            prices.put(product, value);
            if (old > value)
                offerConditions.get(product).signalAll();
        } finally {
            wLock.unlock();
        }
    }

    public double take(@Nonnull Product product) {
        locks.get(product).readLock().lock();
        return prices.get(product);
    }

    public void putBack(@Nonnull Product product) {
        locks.get(product).readLock().unlock();
    }

    public double waitForOffer(@Nonnull Product product,
                               double maximumValue) throws InterruptedException {
        ReadWriteLock rwLock = locks.get(product);
        rwLock.writeLock().lock();
        try {
            while (prices.get(product) > maximumValue)
                offerConditions.get(product).await();
            rwLock.readLock().lock();
        } finally {
            rwLock.writeLock().unlock();
        }
        return prices.get(product);
    }

    public double pay(@Nonnull Product product) {
        double price = prices.get(product);
        locks.get(product).readLock().unlock();
        return price;
    }
}
