/*!
  Funcionalidades da API MPI:
    MPI_COMM_WORLD: agrupa todos os processos criados. É o subconjunto maior. O
                    meu MPI communicator

    MPI_Comm_size(MPI_Comm comm, int *psize): diz quantos processos foram
                            |           |     criados dentro do meu MPI_COMM_WORLD
                            |           |
                            |           |
                            |        ponteiro para a variável
                            |        que armazenará o resultado
                            |        do número de processos criados
                            |
                          MPI communicator

    MPI_Comm_rank(MPI_Comm comm, int *rank): diz qual é o meu rank, ou seja,qual
                          |         |        o número (ID) de um processo
                          |         |
                          |         |
                          |       ponteiro para a variável
                          |       que armazenará o rank do meu
                          |       processo corrente
                          |
                        MPI communicator

  COMPILACAO:
                      $ mpicc hello2.c -o hello2
                      $ mpirun -np 3 .hello2

*/

#include <mpi.h>
#include <stdio.h>

int main (int argc, char ** argv) {
  int size, rank;
  MPI_Init(&argc, &argv);  // inicia o meu ambiente MPI
  MPI_Comm_size(MPI_COMM_WORLD, &size);  //verifica quantos processos from criados e armazena em 'size'
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);  // verifica o rank do meu processo e salva em 'rank'

  if (rank == 0)
    printf("Number of process: %d\n", size);

  printf("Hello World from rank %d\n", rank);

  MPI_Finalize();  // termina o meu ambiente MPI

  return 0;

}
