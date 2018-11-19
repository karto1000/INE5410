/*!
      - Determina que o código em uma região paralela seja executado por SOMENTE
        UMA ÚNICA THREAD.
      - As demais threads aguardam a execução da thread que executou a diretiva
        (exceto) quando 'nowait' é especificado.

        #pragma omp single [atributos]
                            private(var1, var2,...)
                            firstprivate(var1, var2,...)
                            nowait

      BIBLIOTECAS:          #include <stdio.h>
                            #include <stdlib.h>
                            #include <omp.h>
                            #include <time.h>

      COMPILADOR:           $ gcc single.c -fopenmp -o program
                            $ ./program 4 300

*/


#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <time.h>

int main (int argc, char** argv) {

  if (argc < 2 || argc > 2) {
    printf("Error: expected -> ./single 'num_threads'\n");
  } else {
    omp_set_num_threads(atoi(argv[1]));
    #pragma omp parallel
    {
      printf("Thread %d: iniciada\n",omp_get_thread_num());
      #pragma omp single
      printf("Total de threads: %d, thread_num: %d\n",omp_get_num_threads(), omp_get_thread_num());
    }
  }

  return 0;
}
