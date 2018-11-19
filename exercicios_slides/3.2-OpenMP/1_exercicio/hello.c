/*!
  OpenMp é uma API que permite a programação paralela e de memória compartilhada

  ROTINAS:
          omp_set_num_threads(int t): determina o número máximo de threads a
          serem utilizadas na próxima região paralela

          omp_get_num_threads(void): retorna o número de threads dentro de uma
          região paralela

          omp_get_thread_num(void): retorna o identificador único (tipo ID) da
          thread em específico dentro de uma região paralela

          omp_get_num_procs(void): retorna o numero de sokets (processadores/cores)


  BIBLIOTECA:
              #include <omp.h>
  COMPILAÇÃO:
              $ gcc -o program hello.c -fopenmp
              $ ./program 5
*/

#include <stdio.h>
#include <omp.h>  //OpenMp
#include <stdlib.h>  // atoi

int main (int argc, char **argv) {

  if (argc < 2 || argc > 2) {
    printf("Expected compilation: ./hello 'number'\n");
  } else {

    int num_threads = atoi(argv[1]);  // pego o valor de threads passadas na compilação
    omp_set_num_threads(num_threads);
    printf("Numero de sockets: %d\n", omp_get_num_procs());

    #pragma omp parallel  // essa diretiva paraleliza apenas a próxima linha
    printf("Hello World!\n");
    printf("Hello World 2!\n");
    printf("Numero de threads: %d\n", omp_get_num_threads());
    printf(" \n");


    #pragma omp parallel // paraleliza tudo o que estiver dentro dos {}
    {
      printf("Hello World! Identificador: %d, num_threads: %d\n",
      omp_get_thread_num(), omp_get_num_threads());

      printf("Hello World %d!\n", omp_get_thread_num());
    }
  }


  return 0;
}
