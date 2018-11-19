#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int gValue = 0;
pthread_mutex_t gMtx;

// Função usImprime resultados na telaada na correção do exercício -- definida em helper.c
void imprimir_resultados(int n, int** results);

// Função escrita por um engenheiro
void compute(int arg) {
    if (arg < 2) {
        pthread_mutex_lock(&gMtx);   //Solução 2: remover esse lock
        gValue += arg;
        pthread_mutex_unlock(&gMtx); //Solução 2: remover esse unlock
    } else {
        compute(arg - 1);
        compute(arg - 2);
    }
}

// Função wrapper que pode ser usada com pthread_create() para criar uma 
// thread que retorna o resultado de compute(arg
void* compute_thread(void* arg) {
    int* ret = malloc(sizeof(int));
    pthread_mutex_lock(&gMtx);    
    gValue = 0;
    compute(*((int*)arg));
    *ret = gValue;
    pthread_mutex_unlock(&gMtx);
    return ret;
}


//// vvvvvvvvvvvvvvvvvvvvvv   SOLUÇÃO 1  vvvvvvvvvvvvvvvvvvvvvv
//// Reescrever funções para não compartilharem dados
//int compute(int arg) {
//    if (arg < 2) 
//        return arg;
//    else 
//        return compute(arg - 1) + compute(arg - 2);
//}
//void* compute_thread(void* arg) {
//    int* ret = malloc(sizeof(int));
//    gValue = 0;
//    *ret = compute(*((int*)arg));
//    return ret;
//}
//// ^^^^^^^^^^^^^^^^^^^^^^   SOLUÇÃO 1  ^^^^^^^^^^^^^^^^^^^^^^


//// vvvvvvvvvvvvvvvvvvvvvv   SOLUÇÃO 2  vvvvvvvvvvvvvvvvvvvvvv
//void compute(int arg) {
//    if (arg < 2) {
//        //Compute thread já garantiu acesso exclusivo à gValue, dede a
//        //primeira chamada de compute. As chamadas recursivas de
//        //compute, continuam tendo esse acesso exclusivo, e portanto
//        //não precisamos re-adquirir o mutex.  Uma limitação dessa
//        //solução é que se a função compute ainda fosse acessada de
//        //outros lugares que não compute_thread(), teriamos um risco
//        //de que se chamada de outros lugares, o acesso deixe de ser
//        //exclusivo pthread_mutex_lock(&gMtx); //removido
//        gValue += arg;
//        //pthread_mutex_unlock(&gMtx); //removido
//    } else {
//        compute(arg - 1);
//        compute(arg - 2);
//    }
//}
//// vvvvvvvvvvvvvvvvvvvvvv   SOLUÇÃO 2  vvvvvvvvvvvvvvvvvvvvvv

int main(int argc, char** argv) {
    // Temos n_threads?
    if (argc < 2) {
        printf("Uso: %s n_threads x1 x2 ... xn\n", argv[0]);
        return 1;
    }
    // n_threads > 0 e foi dado um x para cada thread?
    int n_threads = atoi(argv[1]);
    if (!n_threads || argc < 2+n_threads) {
        printf("Uso: %s n_threads x1 x2 ... xn\n", argv[0]);
        return 1;
    }

    // vvvvvvvvvvvvvvvvvvvvvv   SOLUÇÃO 3  vvvvvvvvvvvvvvvvvvvvvv
    // Se o mutex for recursivo, o código acima funciona
    pthread_mutexattr_t attrs;
    pthread_mutexattr_init(&attrs);    //inicializa defaults
    //    lock na thread dona do mutex não trava <------+
    //                                              vvvvvvvvv
    pthread_mutexattr_settype(&attrs, PTHREAD_MUTEX_RECURSIVE);
    //            atributos (type=recursive) do mutex
    //                        vvvvvv
    pthread_mutex_init(&gMtx, &attrs);
    // attrs não será mais usado
    pthread_mutexattr_destroy(&attrs);
    // ^^^^^^^^^^^^^^^^^^^^^^   SOLUÇÃO 3  ^^^^^^^^^^^^^^^^^^^^^^

    int args[n_threads];
    int* results[n_threads];
    pthread_t threads[n_threads];
    //Cria threads repassando argv[] correspondente
    for (int i = 0; i < n_threads; ++i)  {
        args[i] = atoi(argv[2+i]);
        pthread_create(&threads[i], NULL, compute_thread, &args[i]);
    }
    // Faz join em todas as threads e salva resultados
    for (int i = 0; i < n_threads; ++i)
        pthread_join(threads[i], (void**)&results[i]);

    // Não usaremos mais o mutex
    pthread_mutex_destroy(&gMtx);

    // Imprime resultados na tela
    // Importante: deve ser chamada para que a correção funcione
    imprimir_resultados(n_threads, results);

    // Faz o free para os resultados criados nas threads
    for (int i = 0; i < n_threads; ++i) 
        free(results[i]);
    
    return 0;
}
