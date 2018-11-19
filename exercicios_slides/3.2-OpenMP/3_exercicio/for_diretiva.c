/*!
    #pragma omp for: permite paralelizar loops de maneira automática, ou seja as
                     iterações do loop são distribuídas e executadas em paralelo
                     pelas threads da região paralela.

                     É utilizada sempre dentro da regiao paralela, e logo apos
                     ela precisa vir um 'for'.

                             |
                             |
                       ______|_______  omp parallel (com 2 threads)
                        |         |
                        |         |
        i[10 até 19]    |         | i[0 até 9]
                        |         |
                      __|_________|___
                             |
                             | a = -1
                             |
                             |



  BIBLIOTECAS:

  COMPILAÇÃO:       $
                    $
*/

#include <omp.h>  // OpenMP
#include <stdio.h>    // out/in
#include <stdlib.h>  // atoi
#include <time.h>  // clock_t

int main (int argc, char **argv) {
  int tamanho_vetor = 36;
  int a[tamanho_vetor], b[tamanho_vetor], c[tamanho_vetor];
  // preeche os meu vetores
  for (int j = 0; j < tamanho_vetor; j++) {
    a[j] = j;
    b[j] = j;
    c[j] = j;
  }

  // faz a soma sequencial
  for (int i = 0; i < tamanho_vetor; i++) {
    c[i] = a[i] + b[i];
  }
  clock_t sequencial = clock();

  clock_t sequencial_end = clock();
  double time_spent_sequencial = (double)(sequencial_end - sequencial)/CLOCKS_PER_SEC;
  printf("tempo sequencial: %f\n", time_spent_sequencial );
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
  clock_t paralelo = clock();
  #pragma omp parallel
  printf("num_threads: %d\n", omp_get_num_threads());
  #pragma omp for
  for(int m = 0; m <tamanho_vetor; m++) {
    c[m] = a[m]+b[m];
  }

  clock_t paralelo_end = clock();
  double time_spent_paralelo = (double) (paralelo_end - paralelo)/CLOCKS_PER_SEC;

  printf("tempo paralelo: %f\n", time_spent_paralelo);

  return 0;
}
