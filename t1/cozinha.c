#include "cozinha.h"
#include "pedido.h"
#include "tarefas.h"
#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>

// sem_t cozinheiros_sem;
// sem_t bocas_sem;
// sem_t frigideiras_sem;
// sem_t garcons_sem;
// sem_t balcao_sem;
// sem_t pedidos_sem;
//pthread_t* lista_pedidos;
pthread_t thread_spag;
pthread_t thread_sopa;
pthread_t thread_carne;

// ----- estruturas para poder passar os parametros para as threads

void cozinha_init (int cozinheiros, int bocas, int frigideiras, int garcons, int tam_balcao) {
  sem_init(&cozinheiros_sem, 0, cozinheiros);
  sem_init(&bocas_sem, 0, bocas);
  sem_init(&frigideiras_sem, 0, frigideiras);
  sem_init(&garcons_sem, 0, garcons);
  sem_init(&balcao_sem, 0, tam_balcao);
  sem_init(&pedidos_sem, 0, 1);
}

//------função thread que ferve a água-----------
void* ferver_agua_func(void* arg) {
  agua_t* agua_ptr = (agua_t*) arg;
  // espera uma boca livre
  sem_wait(&bocas_sem);
  ferver_agua(agua_ptr);
  sem_post(&bocas_sem);
  pthread_exit(NULL);
}

//------------funcao thread que prepara a sopa--------------------
void* sopa_func(void* arg) {
  pedido_t* pedido_ptr = (pedido_t *) arg;
  // espera um cozinheiro livre
  sem_wait(&cozinheiros_sem);
  printf("Pedido %d (SOPA) iniciado!\n", pedido_ptr->id);
  prato_t* prato = create_prato(*pedido_ptr);
  agua_t* agua = create_agua();

  // lança thread para ir fervendo a água
  pthread_t thread_ferver_agua;
  pthread_create(&thread_ferver_agua, NULL,ferver_agua_func, (void*) agua);

  legumes_t* legumes = create_legumes();
  cortar_legumes(legumes);

  // espera a agua esquentar para fazer caldo
  pthread_join(thread_ferver_agua, NULL);
  // espera boca vazia
  sem_wait(&bocas_sem);
  caldo_t* caldo = preparar_caldo(agua);

  cozinhar_legumes(legumes, caldo);
  sem_post(&bocas_sem);
  empratar_sopa(legumes, caldo, prato);

  //espera lugar vago no balcao
  sem_wait(&balcao_sem);
  notificar_prato_no_balcao(prato);
  sem_post(&cozinheiros_sem);
  // espera garcon livre
  sem_wait(&garcons_sem);
  entregar_pedido(prato);
  //libera espaco no balcao e garcon
  sem_post(&balcao_sem);
  sem_post(&garcons_sem);

  free(pedido_ptr);
  //sem_post(&pedidos_sem);
  pthread_exit(NULL);

}

//------função thread que esquenta o molho-----------
void* esquentar_molho_func (void* arg) {

  molho_t* molho = (molho_t*) arg;
  sem_wait(&bocas_sem);
  esquentar_molho(molho);
  sem_post(&bocas_sem);
  pthread_exit(NULL);
}

//------função thread dourar o bacon-----------
void* dourar_bacon_func (void* arg) {
  bacon_t* bacon = (bacon_t*) arg;

  sem_wait(&frigideiras_sem);
  sem_wait(&bocas_sem);
  dourar_bacon(bacon);
  sem_post(&frigideiras_sem);
  sem_post(&bocas_sem);

  pthread_exit(NULL);
}

// ----------funcao thread que prepara spaghetti-------------
void* spag_func(void* arg) {
  pedido_t* pedido_ptr = (pedido_t *) arg;

  // espera um cozinheiro livre
  sem_wait(&cozinheiros_sem);
  printf("Pedido %d (SPAGHETTI) iniciado!\n", pedido_ptr->id);
  prato_t* prato = create_prato(*pedido_ptr);
  molho_t* molho = create_molho();

  // thread para fazer o molho
  pthread_t thread_molho;
  pthread_create(&thread_molho, NULL, esquentar_molho_func, (void*)molho);

  agua_t* agua = create_agua();
  // thread para esquentar a água
  pthread_t thread_ferver_agua;
  pthread_create(&thread_ferver_agua, NULL, ferver_agua_func, (void*) agua);

  bacon_t* bacon = create_bacon();
  // thread para dourar o bacon
  pthread_t thread_dourar_bacon;
  pthread_create(&thread_dourar_bacon, NULL, dourar_bacon_func, (void*) bacon);

  spaghetti_t* spaghetti = create_spaghetti();

  pthread_join(thread_ferver_agua, NULL);
  cozinhar_spaghetti(spaghetti, agua);
  destroy_agua(agua); // estava danod memory leak ai dei um destruir na agua

  pthread_join(thread_molho,NULL);
  pthread_join(thread_dourar_bacon, NULL);
  empratar_spaghetti(spaghetti, molho, bacon, prato);

  sem_wait(&balcao_sem);
  notificar_prato_no_balcao(prato);
  sem_post(&cozinheiros_sem);
  sem_wait(&garcons_sem);
  entregar_pedido(prato);
  sem_post(&balcao_sem);
  sem_post(&garcons_sem);

  free(pedido_ptr);
  //sem_post(&pedidos_sem);
  pthread_exit(NULL);
}

//---------funcao thread que prepara carne----------
void* carne_func(void* arg) {

  pedido_t* pedido_ptr = (pedido_t *) arg;

  // espera um cozinheiro livre
  sem_wait(&cozinheiros_sem);
  printf("Pedido %d (CARNE) iniciado!\n", pedido_ptr->id);
  prato_t* prato = create_prato(*pedido_ptr);
  carne_t* carne = create_carne();
  cortar_carne(carne);
  temperar_carne(carne);
  // espera uma boca e um frigideira liberar
  sem_wait(&bocas_sem);
  sem_wait(&frigideiras_sem);
  grelhar_carne(carne);
  // libera a boca e a frigideira
  sem_post(&bocas_sem);
  sem_post(&frigideiras_sem);
  empratar_carne(carne, prato);
  // espera lugar vago no balcao
  sem_wait(&balcao_sem);
  notificar_prato_no_balcao(prato);
  // libera cozinheiro
  sem_post(&cozinheiros_sem);
  // epsera garcon livre
  sem_wait(&garcons_sem);
  entregar_pedido(prato);
  // libera balcao
  sem_post(&balcao_sem);
  // libera garcon
  sem_post(&garcons_sem);
  free(pedido_ptr);

  //sem_post(&pedidos_sem);
  pthread_exit(NULL);
}


void processar_pedido(pedido_t p) {
    // alocando meu pedido para não eprdere depois de sair de contexto
    pedido_t* pedido = (pedido_t*) malloc(sizeof(pedido_t));
    *pedido = p;

  switch (pedido->prato) {
    case PEDIDO_NULL:
      free(pedido);
      break;
    case PEDIDO_SPAGHETTI:
      printf("Pedido %d (SPAGHETTI) submetido!\n", pedido->id);
      pthread_create(&thread_spag, NULL, spag_func, (void*)pedido);
      break;
    case PEDIDO_SOPA:
      printf("Pedido %d (SOPA) submetido!\n", pedido->id);
      pthread_create(&thread_sopa, NULL, sopa_func, (void*)pedido);
      break;
    case PEDIDO_CARNE:
      printf("Pedido %d (CARNE) submetido!\n", pedido->id);
      pthread_create(&thread_carne, NULL, carne_func,(void*) pedido);
      break;
    case PEDIDO__SIZE:
      free(pedido);
      break;
  }
}

void cozinha_destroy() {
  pthread_join(thread_spag, NULL);
  pthread_join(thread_carne, NULL);
  pthread_join(thread_sopa, NULL);

  sem_destroy(&cozinheiros_sem);
  sem_destroy(&bocas_sem);
  sem_destroy(&frigideiras_sem);
  sem_destroy(&garcons_sem);
  sem_destroy(&balcao_sem);
}
