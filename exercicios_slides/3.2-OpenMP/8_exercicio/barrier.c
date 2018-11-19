/*!
      -PESQUISAR


      BIBLIOTECAS:          #include <stdio.h>
                            #include <stdlib.h>
                            #include <omp.h>


      COMPILADOR:           $ gcc barrier.c -fopenmp -o program
                            $ ./program 4 300

*/

#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main (int argc, char **argv) {

  if (argc < 2 || argc > 2) {
    printf("Error: expected -> ./single 'num_threads'\n");
  } else {

  }
  return 0;
}
