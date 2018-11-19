/*!
  Bloqueio de processos por meio de mensagem, ou seja, o processo bloqueia a execução
  e os destinatário espera at eu receba a mensagem de desbloqueio

        processo 0          processo 1
            |                   |
            |                   | MPI_Recv()
            |                   |     T
 MPI_Send() |---                |     |
            |   ---             |     |
            |      ---          |     |  Bloqueio
            |         ---       |     |
            |            ---    |     |
            |               --- |     |
            |                   |


*/


#include <mpi.h>
#include <stdio.h>

int main (int argc, char ** argv) {
  int size, rank;
  MPI_Init(&argc, &argv);  // inicia meu ambiente MPI
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);

  if (rank == 0) {  // rank = 0 envia mensagem para todos os outros processos
    int dsend = 42;
    for (int i = 1; i < size; i++) {
      MPI_Send(&dsend, 1, MPI_INT, i, 0, MPI_COMM_WORLD);
    }
  } else {  // todos outros processos recebem a mensagem do rank = 0
    int drec;
    MPI_Recv(&drec, 1, MPI_INT, 0, MPI_ANY_TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
  }
  MPI_Finalize();  //termina meu ambiente MPI

  return 0;
}
