#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

//                 (main)
//                    |
//    +----------+----+------------+
//    |          |                 |
// worker_1   worker_2   ....   worker_n


// ~~~ argumentos (argc, argv) ~~~
// ./program n_threads

// ~~~ printfs  ~~~
// pai (ao criar filho): "Contador: %d\n"
// pai (ao criar filho): "Esperado: %d\n"

// Obs:
// - pai deve criar n_threds (argv[1]) worker threads
// - cada thread deve incrementar contador_global n_threads*1000
// - pai deve esperar pelas worker threads  antes de imprimir!

/*! Nesse código eu adicionei um mutex para não acontecer de duas threads
tentarem incrementar a variavel global (contador_global)*/ 

int contador_global = 0;
int valor = 0;
pthread_mutex_t lock;

// func que incrementa a variavel global
void* func_thread(void* arg) {
  int loop = *(int*)arg;
  //printf("loop func_thread: %d\n", loop );
  for (int i = 0; i<loop; i++) {
    pthread_mutex_lock(&lock);
    contador_global++;
    pthread_mutex_unlock(&lock);

  }

  pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("n_threads é obrigatório!\n");
        printf("Uso: %s n_threads\n", argv[0]);
        return 1;
    }
    int n_threads = atoi(argv[1]);
    printf("n_threads: %d\n", n_threads);
    int loop = n_threads*1000;
    //printf("loop main: %d\n", loop );
    // array com identificador das threads
    pthread_t threads[n_threads];

    //loop que cria as threads
    for(int i =0; i<n_threads; i++) {
      pthread_create(&threads[i], NULL, func_thread, (void*)&loop);
    }

    for(int i=0; i <n_threads; i++) {
      pthread_join(threads[i], NULL);
    }

    pthread_mutex_destroy(&lock);

    printf("Contador: %d\n", contador_global);
    printf("Esperado: %d\n", n_threads*n_threads*1000);
    return 0;
}
