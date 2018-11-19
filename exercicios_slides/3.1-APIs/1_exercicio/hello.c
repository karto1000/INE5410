/*!

  MPI_Init: inicia o meu ambiente MPI
  MPI_Finalize: finaliza o meu ambiente MPI


  Tudo o que está dentro do meu ambiente MPI será paralelizado pelos meus
  processos criados

                    | <- processo único
                    |
                   MPI
                |  | ...| |
                |  | ...| | <- processos paralelizados
                |  | ...| |
                  fim MPI
                    |
                    | <- processo único novamente
                    |

  COMPILAÇÃO:
                        $ mpicc hello.c -o Hello
                        $ mpirun -np 3 ./hello
*/

#include <mpi.h>
#include <stdio.h>

int main (int argc, char **argv) {
  MPI_Init(&argc, &argv);  // inicializa o ambiente MPI

  printf("Hello World!\n");

  MPI_Finalize();  // finaliza o ambiente MPI

  return 0;
}
