/*!
      - Determina que o código em uma região paralela seja executado por SOMENTE
        UMA ÚNICA THREAD POR VEZ.
      - Em outras palavras, será feita uma exclusão mútua na região protegida paralela
        diretiva.

      #pragma omp critical

      BIBLIOTECAS:          #include <stdio.h>
                            #include <stdlib.h>
                            #include <omp.h>


      COMPILADOR:           $ gcc critical.c -fopenmp -o program
                            $ ./program 4

*/

#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main (int argc, char **argv) {

  if (argc < 2 || argc > 2) {
    printf("Error: expected -> ./critical 'num_threads'\n");
  } else {
    omp_set_num_threads(atoi(argv[1]));
    int x = 0;
    #pragma omp parallel shared(x)
    {
      #pragma omp critical
      x++;
    }

    printf("x: %d\n", x);
  }
  return 0;
}
