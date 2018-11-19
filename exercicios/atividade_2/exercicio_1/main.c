/*
========================================================================
Name					: main.c
Exercise      : exercicio_1
Author				: Rafael Neves de Mello Oliveira
Copyright			:
Description		: Você deve escrever um programa em C em que o processo pai
                crie 2 processos filhos (fork()).
                Para cada processo filho criado, o processo pai deve imprimir
                "Processo pai crio XX",onde XX é o PID do processo criado.
                Cada processo filho deve apenas imprimir "Processo filho XX
                criado", onde XX é o PID do processo corrente (use a função
                getpid() para isso).
                O proceso pai (e apenas ele) deve imprimir "Processo pai
                finalizado", somente após os filhos terminarem (use a função
                wait() para assegurar que os filhos terminem de executar).

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
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>

//       (pai)
//         |
//    +----+----+
//    |         |
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!


int main(int argc, char** argv) {
//
//     // ....
//     printf("PID pai: %d\n", getpid());
// 	int filho_1 = fork();  // cria uma cópia do processo
//
// 	if(filho_1 > 0) {  // É o processo pai
// //--------Código do processo Pai ----------------//
// 		printf("Processo pai criou %d\n", filho_1);
//
// 		int status;
// 		wait(&status);
// 		int filho_2 = fork();
// 		if (filho_2 > 0) {  // É o processo pai
// //--------Código do processo pai-----------------//
// 			printf("Processo pai criou %d\n", filho_2);
// 			while(wait(NULL) > 0);
// 		} else if (filho_2 == 0) {  // É o processo filho_2
// //----------Código do processo filho_2 -----------//
// 			printf("Processo filho_2 %d criado\n", getpid());
// 			exit(0);
// 		} else {
// 			printf("Erro\n");
// 		}
//
// 	} else if (filho_1 == 0){  // É o processo filho_1
// //--------Código do processo Pai ----------------//
// 		printf("Processo filho_1 %d criado \n", getpid());
// 		exit(0);
// 	} else {  // houve erro na criação
// 		printf("Erro\n");
// 	}
//
//     printf("Processo pai finalizado!\n");
//     return 0;

//-------------------------solucao 2-----------------------
  printf("PID: %d\n", getpid());  // Printa o PID do pai
  for(int i = 0; i < 2; i++) {
    // 1 = true = fork() = pai
    // 0 = false = !fork() = filho
    /*!
      caso não for o filho não vai entrar no 'if' abaixo e vai continuar
      rodando o código depois do 'if', ou seja, printa que criou um filho e
      espera esse filho terminar de executar e só então vai incrementar o 'for'
      novamente
    */
    if(!fork()) { // assegura que é um filho
        printf("Processo filho %d: %d criado\n", i +1, getpid());
        return 0;
    }
    printf("processo pai criou %d\n", getpid());
    int status;
    /*!
    Suspende o processo pai (calling process) até que um de seus filhos termine
    como no caso estou criando um filho de cada vez ele espera até seu filho
    termine
    */
    wait(&status);
  }
  printf("Processo pai finalizado\n");

}
