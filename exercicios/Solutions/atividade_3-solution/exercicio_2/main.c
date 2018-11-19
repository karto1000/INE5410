#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

// Lê o conteúdo do arquivo filename e retorna um vetor E o tamanho dele
// Se filename for da forma "gen:%d", gera um vetor aleatório com %d elementos
//
// +-------> retorno da função, ponteiro para vetor malloc()ado e preenchido
// |         usado como 2o retorno! <-----+
// v                                      v
double* load_vector(const char* filename, int* out_size);


// "Classe" de argumento data para threads que executam a função work
struct params {
    double* a; //lado esquerdo da adição
    double* b; //lado direito da adição
    double* c; //resultado
    int begin; //primeiro índice dentro de a,b,c onde a thread deve computar
    int end;   //primeiro índice após o intervalo  dentro de a,b,c onde a thread deve computar,
               //ou seja, o "último índice que a thread deve computar" + 1.
               //Isso é idiomático de C/C++ e facilita algumas contas
};

void *work(void *arg) {
    struct params param = *(struct params *)arg;

    /* soma dos vetores */ 
    for (int i = param.begin; i < param.end; i++)
        param.c[i] = param.a[i] + param.b[i];

    pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
    srand(time(NULL));

    //Temos argumentos suficientes?
    if(argc < 4) {
        printf("Uso: %s n_threads a_file b_file [-silent]\n"
               "    n_threads    número de threads a serem usadas na computação\n"
               "    *_file       caminho de arquivo ou uma expressão com a forma gen:N,\n"
               "                 representando um vetor aleatório de tamanho N\n"
               "    -silent      não imprime resultado na saída\n", argv[0]);
        return 1;
    }
  
    //Quantas threads?
    int n_threads = atoi(argv[1]);
    if (!n_threads) {
        printf("Número de threads deve ser > 0\n");
        return 1;
    }
    //Lê números de arquivos para vetores alocados com malloc
    int a_size = 0, b_size = 0;
    double* a = load_vector(argv[2], &a_size);
    if (!a) {
        //load_vector não conseguiu abrir o arquivo
        printf("Erro ao ler arquivo %s\n", argv[2]);
        return 1;
    }
    double* b = load_vector(argv[3], &b_size);
    if (!b) {
        printf("Erro ao ler arquivo %s\n", argv[3]);
        return 1;
    }
    int silent = argc > 4 && strcmp(argv[4], "-silent") == 0;
                           //^--->  0 se argv[4] == "-silent"
                           //|---> -1 se argv[4] <  "-silent"
                           //+---> +1 se argv[4] >  "-silent"
    
    //Garante que entradas são compatíveis
    if (a_size != b_size) {
        printf("Vetores a e b tem tamanhos diferentes! (%d != %d)\n", a_size, b_size);
        return 1;
    }
    //Cria vetor do resultado
    double* c = malloc(a_size*sizeof(double));
  
    //Garante que não serão criadas threads demais
    if(n_threads > a_size)
        n_threads = a_size;

    //Guarda pthread_t de cada thread criada
    pthread_t threads[n_threads];
    //Precisamos de um array fora do loop. Se criarmos dentro do loop, onde não
    //precisa ser array, teremos um dangling pointer!!!
    //Quando uma thread for seguir o ponteiro, a thread principal já terá colocado 
    //outra coisa naquela região de memória, semeando a discórdia
    struct params parameters[n_threads]; 
    // Divisão de trabalho para 10 itens entre 3 threads:
    //             +--------------------------------------+
    //    indices  |0   1   2 | 3   4   5 | 6   7   8   9 |
    //    threads  |    1     |     2     |       3       |
    //             +--------------------------------------+
    //                                                  ^
    //                        resto da divisão! <-------+
    int chunk = a_size/n_threads;

    for (int i = 0; i < n_threads; ++i) {
        parameters[i].a = a; parameters[i].b = b; parameters[i].c = c;
        parameters[i].begin = i*chunk; //se chunk==3, thread 0 -> 0; 1 -> 3; 2 -> 6
        parameters[i].end = parameters[i].begin + chunk // <-- igual para toda thread
                          + (i == n_threads-1 ? (a_size - n_threads*chunk) : 0);
                          //      ^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^ 
                          //  (última thread)           (resto da divisão)
        pthread_create(&threads[i], NULL, work, &parameters[i]);
    }

    //Espera todo mundo terminar
    for (int i = 0; i < n_threads; i++)
        pthread_join(threads[i], NULL);
    
    //Imprime resultados
    if (!silent) {
        for (int i = 0; i < a_size; ++i) 
            printf("%s%g", i ? " " : "", c[i]);
        printf("\n");
    }

    //Importante: libera memória
    free(a);
    free(b);
    free(c);

    return 0;
}
