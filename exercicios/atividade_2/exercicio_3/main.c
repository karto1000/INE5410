/*
========================================================================
Name					: main.c
Exercise      : exercicio_3
Author				: Rafael Neves de Mello Oliveira
Copyright			:
Description		: Escreva um programa C que imprima "Processo principal
                iniciado" e crie um processo filho, que:
                Imprima "Processo XX iniciado", onde XX é o PID desse processo
                filho.

                Troque seu binário (função execlp()) pelo binário grep, de
                modo a executar o comando grep silver text, onde text é um
                arquivo texto incluído no .tar.gz inicial.

                O pai deve aguardar pelo término do processo filho. Caso o
                processo filho termine com código 0, o processo pai deve
                imprimir "Filho retornou com código 0, encontrou silver";
                caso contrário, deve imprimir "Filho retornou com código XX,
                não encontrou silver", onde XX é código de saída do processo
                filho (grep).O arquivo text fornecido contém a palavra silver,
                logo o grep imprimirá a frase contendo essa palavra e
                terminará com código 0. Se o arquivo for alterado (removendo
                a palavra) grep não imprimirá nada e retornará 1. Se o
                arquivo text for removido ou renomeado, grep retornará 2
                e imprimirá uma mensagem de erro.

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


#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

//    (pai)
//      |
//   filho_1

// ~~~ printfs  ~~~
//        filho (ao iniciar): "Processo %d iniciado\n"
//          pai (ao iniciar): "Processo pai iniciado\n"
// pai (após filho terminar): "Filho retornou com código %d,%s encontrou silver\n"
//                            , onde %s é
//                              - ""    , se filho saiu com código 0
//                              - " não" , caso contrário

// Obs:
// - processo pai deve esperar pelo filho
// - filho deve trocar seu binário para executar "grep silver text"
//   + dica: use execlp(char*, char*...)
//   + dica: em "grep silver text",  argv = {"grep", "silver", "text"}

int main(int argc, char** argv) {
    printf("Processo principal iniciado\n");
    fflush(stdout);
    pid_t filho = fork();

    if (filho == 0) {
      printf("Processo %d iniciado\n",getpid());
      fflush(stdout);
      execlp("grep", "grep", "silver", "text", NULL);
      //return 0;
    } else {
      int status;
      while(!WIFEXITED(status)) {
        waitpid(filho, &status, 0);
      }
      int code = WEXITSTATUS(status);
      printf("Filho retornou com código %d, %s encontrou silver\n",
      code, code ? "não" : "" );
      //wait(&status);

    }

    return 0;
}

// int main(int argc, char** argv) {
//     printf("Processo principal iniciado\n");
//     fflush(stdout);
//     pid_t child = fork();
//     if (child) {
//         int stat;
//         do {
//             waitpid(child, &stat, 0);
//         } while (!WIFEXITED(stat));
//         int code = WEXITSTATUS(stat);
//         printf("Filho retornou com código %d,%s encontrou silver\n",
//                code, code ? "não" : "");
//     } else {
//         printf("Processo %d iniciado\n", getpid());
//         fflush(stdout);
//         execlp("grep", "grep", "silver", "text", NULL);
//     }
//
//     return 0;
// }
