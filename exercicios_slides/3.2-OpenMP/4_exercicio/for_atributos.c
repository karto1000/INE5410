/*!

    É utilizado para paralelizar loops:

    #pragma omp for [atributos]
                    scheduale(tipo,[,chunk])
                    ordered
                    nowait
                    private(var1, var2,...)
                    firstprivate(var1, var2,...)
                    reduction(operador: var1, var2,...)

    scheduale(tipo, [,chunk]): Define como as iterações serão divididas entre as
                              threads.

        chunk: tamanho dos blocos de loops
        tipos: static(padrao), dynamic, guided.

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
        scheduale(static): as iterações são divididas em igual partes de acordo
                          com o numero de threads

        Ex.: loop = 40; threads = 4;

        scheduale(static)
                            i=0       i=10      i=20      i=30
                           _____________________________________
                          |  t0    |   t1    |    t2   |  t3    |
                          |________|_________|_________|________|
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
        scheduale(static, 5): as iterações são divididas entre as threads de acordo
                              com o tamanho do chunk, e as threads executam as
                              iterações na ordem;

        Ex.: loop = 40; threads = 4;

        scheduale(static, 5)

                        i=0    i=5  i=10   i=15  i=20  i=25  i=30  i=35
                         _______________________________________________
                        |  t0 | t1  | t2  | t3  | t0  | t1  | t2  |  t3 |
                        |_____|_____|_____|_____|_____|_____|_____|_____|
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

        scheduale(dynamic, 5): as iterações são divididas entre as threads de acordo
                                com a liberação delas, ou seja, assim que um thread
                                fica ociosa ela entra na fila para pegar o proximo
                                'trabalho'
        Ex.: loop = 40; threads = 4;

        scheduale(dynamic, 5)

                        i=0    i=5  i=10   i=15  i=20  i=25  i=30  i=35
                         _______________________________________________
                        |  t2 | t0  | t1  | t2  | t0  | t3  | t1  |  t3 |
                        |_____|_____|_____|_____|_____|_____|_____|_____|

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
        scheduale(guides, 5): o tamanho dos blocos de iterações são reduzidos
                              exponencialmente toda vez que um bloco é dado padrao
                              uma thread, o chunk aqui define o tamanho mínimo
                              aproximado. Aqui funciona como no dynamic, assim que
                              uma thread fica ociosa ela entra na fila pra pegar
                              mais um trabalho

        Ex.: loop = 40; threads = 4;

        scheduale(guided, 5)

              i=0           i=10     i=18    i=25   i=31  i=35  i=38
               ____________________________________________________
              |  t2        |     t1  |   t0  | t3   | t0  | t2 | t1|
              |____________|_________|_______|______|_____|____|___|


*/


#include <stdio.h>
#include <stdlib.h>  // atoi
#include <omp.h>  // omp
#include <time.h> // clock_t

int main (int argc, char **argv) {

  if (argc < 3 || argc > 3) {
    printf("Error: expected -> ./program 'num_threads' 'num_iteracoes'\n");
  } else {

    int n = atoi(argv[2]);
    int soma_seq = 0, soma_paral = 0;
    int a[n], b[n], c[n], d[n];
    double time_spent_seq = 0, time_spent_paralel = 0;

    omp_set_num_threads(atoi(argv[1]));  // pega o tanto de threads a serem usadas nas regioes paralelas
    int num_threads = 0;
    for(int i = 0; i <n; i++) {
      a[i] = i;
      b[i] = i+1;
      c[i] = i;
      d[i] = i+1;
    }
    clock_t begin_seq = clock();
    for(int i=0; i<n; i++) {
      soma_seq += a[i] * b[i];
    }
    clock_t end_seq = clock();
    time_spent_seq = (double)(end_seq - begin_seq)/CLOCKS_PER_SEC;

    /*! as variáveis são compartilhadas, ou seja eu não crio cópias
    aqui dentro da região de paralelismo*/
    clock_t begin_paralel = clock();
    #pragma omp parallel shared(a, b)
    {

      num_threads = omp_get_num_threads();

      /*! scheduale (static):divide o meu loop pelo numero de
      threads de igual forma.
      reduction(+: soma): cria cópias da minha variável
      soma_paral e inicializa com '0' pq eu estou usando
      o operador '+'*/
      #pragma omp for schedule (dynamic, num_threads)  reduction(+:soma_paral)
      for (int i = 0; i<n;i++) {
        soma_paral +=a[i]*b[i];
      }
    }
    clock_t end_paralel = clock();
    time_spent_paralel = (double) (end_paralel - begin_paralel)/CLOCKS_PER_SEC;

    printf("num_threads: %d\n", num_threads);


    printf("soma_seq: %d\n", soma_seq);
    printf("soma_paral: %d\n\n", soma_paral);

    printf("time_spent_seq: %f\n", time_spent_seq);
    printf("time_spent_paralel: %f\n", time_spent_paralel);
  }



  return 0;
}
