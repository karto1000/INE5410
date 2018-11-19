#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <time.h>

// Matrizes a serem multiplicadas
extern int **matriz1;
extern int **matriz2;
// Matriz resultante
extern int **resultado;
// Argumento de linha de comando
extern int tamanho_matriz;
// Usados em multiplicar_thread
extern int linha_atual, coluna_atual;
//^^^^
// |       extern acessa uma global definida em outro arquivo. Sem o extern,
// +---->  estariamos criando uma global DIFERENTE.
// |
//vvvv
extern pthread_mutex_t matrix_mutex;

// Todas as worker threads executam essa função paralelamente.
// Em algum lugar aqui ocorre um data race. Quando há mais de uma thread,
// o resultado da multiplicação quase sempre fica errado.
//
// Há uma seção de código nessa função que é conflituosa: duas ou mais
// threads entram em condição de corrida ao ler/alterar algumas variáveis
// globais. Você deve identificar essa seção e protegê-la com um mutex. Se
// você considerar que a função inteira é essa seção, o problema estará
// resolvido, mas NÃO HAVERÁ PARALELISMO SENDO EXPLORADO.
//
// O programa precisa ser RÁPIDO E CORRETO.
void *multiplicar_thread(void *arg) {
    int i;
    int minha_linha, minha_coluna;

    // Essa operação de leitura desprotegida em linha_atual
    // é segura por dois motivos:
    // 1. Se lermos enquanto outra thread está na seção crítica, no pior
    //    caso entraremos no loop e tentaremos obter a seção crítica.
    // 2. Se lermos linha_atual >= tamanho_matriz, não entraremos no loop.
    //    Mas não há risco de perder uma linha da matriz resultado, pois
    //    nenhuma thread que esteja na seção crítica decrementará linha_atual.
    while (linha_atual < tamanho_matriz) {
        //adquire o mutex
        pthread_mutex_lock(&matrix_mutex);
        minha_linha = linha_atual;
        minha_coluna = coluna_atual;

        coluna_atual += 1;
        if (coluna_atual >= tamanho_matriz) {
            coluna_atual = 0;
            linha_atual += 1;
        }
        //fim da seção crítica, libera
        pthread_mutex_unlock(&matrix_mutex);
        //Daqui pra baixo, não são mais feitas leituras ou escritas em
        //{linha,coluna}_atual. As demais variáveis sendo acessadas:
        //1. São locais, ou;
        //2. São globais, mas serão acessadas apenas por essa thread

        if (minha_linha >= tamanho_matriz)
            break;

        for (i = 0; i < tamanho_matriz; i++) {
            resultado[minha_linha][minha_coluna] += matriz1[minha_linha][i] * matriz2[i][minha_coluna];
        }
    }

    return NULL;
}
