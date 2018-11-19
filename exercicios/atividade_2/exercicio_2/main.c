/*
========================================================================
Name					: main.c
Exercise      : exercicio_2
Author				: Rafael Neves de Mello Oliveira
Copyright			:
Description		: Você deve escrever um programa C em que:
                O processo principal crie 2 processos filhos.

                Cada um dos processos filhos deve, por sua vez, criar mais
                três processos.

                Cada processo filho (tanto do processo principal quanto dos
                criados no passo anterior) deve imprimir "Processo XX, filho
                de YYY", onde XX é o PID do processo em questão e YYY o PID
                do processo que o criou (use as funções getpid() e getppid()
                para isso).

                Os filhos de segundo nível (filhos dos filhos do processo
                principal) devem, após imprimir esta mensagem, aguardar 5
                segundos antes de terminar (use a função sleep() para isso).

                Os processos que criaram filhos devem aguardar que seus filhos
                terminem de executar (utilize a função wait()).

                Todos os processos filhos devem imprimir, ao finalizar,
                "Processo XX finalizado", onde XX é o PID do processo em
                questão. O processo principal deve imprimir "Processo
                principal XX finalizado", onde XX é o PID do processo
                principal.

Dica         : Você deve fazer uma chamada da função wait() ou waitpid()
              para cada processo filho criado. Esta função deve ser chamada
              somente depois de todos os filhos do processo em questão terem
              sido criados.

              O valor de stat em wait(&stat) ou waitpid(pid, &stat, 0) é um
              aglomerado de outras variáveis. Use macros como WFEXITED e
              WFEXITSTATUS, descritas na documentação.

              Há desenhos em ASCII dentro dos arquivos .c iniciais que
              complementam a especificação.

              Garantam que os printfs estão como solicitado e na ordem
              solicitada (Há uma lista dos printfs no começo de cada
              arquivo .c)

              A função printf não imprime imediatamente na saída, mas sim
              em um buffer. Se a saída está conectada em um terminal, cada
              \n causa um fflush(stdio). O script de correção redireciona
              a saída do teu programa, portanto não há flush a cada \n. Em
              combinação com fork(), prints podem ocorrer mais de uma vez!
              Os scripts corretores vão te avisar quando você esquecer do
              fflush e vão dizer onde você deve colocá-lo.

              A função exit(<status>) pode ser usada para encerrar um
              processo em qualquer ponto do código.

              Para tornar o código mais legível, crie funções separadas
              para cada tipo de processo filho (uma função para filhos do
              processo principal, outra função para filhos dos filhos do
              processo principal)

              Você vai precisar das seguintes bibliotecas em seu código:
              #include <stdlib.h>
              #include <unistd.h>
              #include <sys/types.h>
              #include <sys/wait.h>
              #include <stdio.h>
              #include <string.h>

========================================================================
*/

#include <stdlib.h>
// Biblioteca que me permite usar a função sleep()
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>

//                          (principal)
//                               |
//              +----------------+--------------+
//              |                               |
//           filho_1                         filho_2
//              |                               |
//    +---------+-----------+          +--------+--------+
//    |         |           |          |        |        |
// neto_1_1  neto_1_2  neto_1_3     neto_2_1 neto_2_2 neto_2_3

// ~~~ printfs  ~~~
//      principal (ao finalizar): "Processo principal %d finalizado\n"
// filhos e netos (ao finalizar): "Processo %d finalizado\n"
//    filhos e netos (ao inciar): "Processo %d, filho de %d\n"

// Obs:
// - netos devem esperar 5 segundos antes de imprmir a mensagem de finalizado
// (e terminar)
// - pais devem esperar pelos seu descendentes diretos antes de terminar

int main(int argc, char** argv) {
  printf("PID: %d\n", getpid());

  for(int i = 0; i < 2; i++) {
    // 1 = true = fork() = pai
    // 0 = false = !fork() = filho
    if(!fork()) {  // assegura que é o filho
      printf("Processo %d, filho de %d\n", getpid(), getppid());
      fflush(stdout);
      for(int j = 0; j< 3; j++) {
        // 1 = true = fork() = pai;
        // 0 = false = !fork() = filho;
        /*!
          caso não for o processo filho ele continua a percorrer o código
          pulando o 'if', ou seja ele cria os proximos filhos
        */
        if(!fork()) {  // assegura que é o filho do filho (neto)
          printf("Processo %d, filho de %d\n",getpid(),getppid());
          sleep(5);
          printf("Processo %d finalizado!\n",getpid());
          return 0;
        }
      }
      /*!
        espera até que não tenha mais nenhum neto, ou seja wait = -1;
      */
      //int statusNetos;
      while(wait(0)>=0);
      printf("Processo %d finalizado!\n", getpid());
      return 0;
    }
  }
  /*!
    espera até que não tenha mais nenhum filho
  */
  //int statusFilhos;
  while(wait(0)>=0);
  printf("Processo principal %d finalizado\n", getpid());
  return 0;
}
