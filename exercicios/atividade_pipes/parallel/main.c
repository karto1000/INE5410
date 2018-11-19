#include "dagostrophism.h" 

//Habilita a função fdopen(). 200809L corresponde ao POSIX de 2008, mas um valor de 1 (POSIX.1, 1990) já seria suficiente.
#define _POSIX_C_SOURCE 200809L 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define N_CHILDREN 4

//                (pai)
//                  |
//    +--------+----+----+--------+
//    |        |         |        |
// filho_1  filho_2   filho_3  filho_4

// ~~~ printfs  ~~~
//  pai (ao terminar): "Palavras dagostróficas: %d\n"

// IMPORTANTE: consulte ../exercicio4-single_proc para a implementação 
// com um único processo. Sua implementação deve ter o mesmo comportamento!

// Obs:
// - pai deve usar pipes para se comunicar com os filhos (cf. exemplo-pipes)
// - pai deve ler palavras e distribuir elas entre o filhos
//   +---------------------------------------------------------
//   |      entrada | plv1 plv2 plv3 plv4 plv5 plv6 plv8  ...
//   |--------------+------------------------------------------
//   |filho destino | 1    2    3    4    1    2    3     ...
//   +---------------------------------------------------------
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

    // ....
   
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
