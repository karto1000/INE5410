#include "dagostrophism.h" 

//Habilita a função fdopen(). 200809L corresponde ao POSIX de 2008, mas um valor de 1 (POSIX.1, 1990) já seria suficiente.
#define _POSIX_C_SOURCE 200809L 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define N_CHILDREN 4

//                (pai)
//                  |
//    +--------+----+----+--------+
//    |        |         |        |
// filho_1  filho_2   filho_3  filho_4

// ~~~ printfs  ~~~
//        pai (ao terminar): "Palavras dagostróficas: %d\n"

// Obs:
// - pai deve usar pipes para se comunicar com os filhos (cf. exemplo-pipes)
// - pai deve ler palavras e distribuir elas entre o filhos
//   +---------------------------------------------------------
//   |      entrada | plv1 plv2 plv3 plv4 plv5 plv6 plv8  ...
//   |--------------+------------------------------------------
//   |filho destino | 1    2    3    4    1    2    3     ...
//   +---------------------------------------------------------
// - quando as palavras terminam, o pai fecha o pipe de palavras
// - cada filho deve enviar ao pai o número de palavras dagostróficas
// - o pai soma as contagens e apenas ele deve mostrar a mensagem com o total


int child_main(int downstream, int upstream);

int main(int argc, char** argv) {
    //Total de palavras dagostróficas
    int total = 0;
    //Matriz de pipes              //               (read_end) | (write_end)
    //                             //                    0     |       1
    int downstream[N_CHILDREN][2]; // (filho_1) 0   up[0][0]   |  up[0][1]
    int   upstream[N_CHILDREN][2]; // (filho_2) 1   up[1][0]   |  up[1][1]  
                                   // (filho_3) 2   up[2][0]   |  up[2][1]  
                                   // (filho_4) 3   up[3][0]   |  up[3][1]  
    //pid's dos filhos
    pid_t children[N_CHILDREN];

    //Cria N_CHILDREN filhos e 2 pipes pra cada filho
    for (int i = 0; i < N_CHILDREN; ++i) { // Para cada filho...
        //Cria um pipe onde o pai escreve e o filho lê
        if (pipe(downstream[i])) {
            printf("Error creating downstream pipe for child %d\n", i);
            return 1;
        }
        //Convert os file descriptors (int) em file streams (FILE*)
        //Cria um pipe onde o filho escreve e o pai lê
        if (pipe(upstream[i])) {
            printf("Error creating upstream pipe for child %d\n", i);
            return 1;
        }
        //Cria filho e prepara pipes
        if (!(children[i] = fork())) {
            // (executado pelos filhos)
            close(downstream[i][1]); //fecha write_end (filho só lê)
            close(  upstream[i][0]); //fecha  read_end (filho só escreve)
            //filho executa child_main() e termina
            return child_main(downstream[i][0], upstream[i][1]); 
        } else {
            // (executado pelo pai)
            close(downstream[i][0]); //fecha  read_end (pai só escreve)
            close(  upstream[i][1]); //fecha write_end (pai só lê)
        }
    }

    // Lê as palavras e distribui entre os filhos
    char word[4096] = {0};
    for (int i = 0; scanf("%4096s", word) > 0; i = (i+1) % N_CHILDREN) {
        //               +----> alterna entre os filhos: 0 1 2 3 0 1 ...
        //               |  +-----> fd de saída (write_end)
        //               v  v                     
        write(downstream[i][1], word, strlen(word));
        //envia um espaço, para que o filho consiga separar as palavras
        write(downstream[i][1], " ", 1);
    }

    //Fecha nosso lado do downstream de cada filho. Isso causará EOF nos filhos
    //Sem esse passo, os filhos ficam travados esperando por novas palavras
    for (int i = 0; i < N_CHILDREN; ++i) {
        close(downstream[i][1]);
    }

    //Coleta resultados
    for (int i = 0; i < N_CHILDREN; ++i) {
        //Espera o filho terminar ...
        int status = 0;
        do {
            waitpid(children[i], &status, 0);
        } while(!WIFEXITED(status) && !WIFSIGNALED(status));
        if (WEXITSTATUS(status)) { // ... e checa se terminou normalmente
            printf("ERRO: Filho %d terminou com status  %d\n", i, 
                   WEXITSTATUS(status));
            return 1;
        }
        //Lê a contagem de dagostróficas do pipe
        char buf[20] = {0};
        //               +-------> fd de entrada (read_end)
        //               v
        read(upstream[i][0], buf, 20);
        total += atoi(buf);
    }

    // fecha o read_end do upstream de cada filho
    for (int i = 0; i < N_CHILDREN; ++i) {
        close(upstream[i][0]); 
    }
    
    printf("Palavras dagostróficas: %d\n", total);
}

int child_main(int downstream, int upstream) {
    int total = 0;
    // scanf() só funcionado com FILE*. 
    // cria um FILE* para acesso ao pipe downstream
    FILE* downstream_file = fdopen(downstream, "r");

    char word[4096];
    while (fscanf(downstream_file, "%4096s", word) > 0)
        total += is_dagostrophic(word);

    //Envia o total como uma string. usa word como buffer
    sprintf(word, "%d", total);
    write(upstream, word, strlen(word)+1);
    fclose(downstream_file); // tambem fecha downstream
    close(upstream);         // fecha nosso lado do pipe
    return 0;
}
