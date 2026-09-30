import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const ConferidorApp());
}

class Lancamento {
  final String data;
  final String descricao;
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacoes;

  Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    this.parcelaAtual,
    this.totalParcelas,
    this.observacoes = '',
  });

  bool get parcelada =>
      parcelaAtual != null && totalParcelas != null;
}

class ResultadoFatura {
  final double? totalFatura;
  final double? totalCartaoInformado;
  final double? totalInternacionalInformado;
  final double? totalServicosInformado;

  final List<Lancamento> lancamentos;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
  });

  double get soma {
    return lancamentos.fold(
      0.0,
      (total, item) => total + item.valor,
    );
  }

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  int get quantidadeParceladas {
    return lancamentos.where((e) => e.parcelada).length;
  }

  bool get conciliada {
    if (diferenca == null) return false;
    return diferenca!.abs() < 0.01;
  }
}

class ParserItau {
  static double moeda(String valor) {
    var texto = valor.trim();

    bool negativo = texto.startsWith('-');

    texto = texto
        .replaceAll('-', '')
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(' ', '');

    final numero = double.tryParse(texto) ?? 0.0;

    return negativo ? -numero : numero;
  }

  static double? procurarValor(
    String texto,
    RegExp expressao,
  ) {
    final match = expressao.firstMatch(texto);

    if (match == null || match.group(1) == null) {
      return null;
    }

    return moeda(match.group(1)!);
  }

  static String limparDescricao(String texto) {
    var resultado = texto;

    resultado = resultado
        .replaceAll(
          RegExp(
            r'Lançamentos:\s*compras\s*e\s*saques',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'DATAESTABELECIMENTOVALOR\s*EM\s*R\$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return resultado;
  }

  static String detectarCategoria(String bloco) {
    final minusculo = bloco.toLowerCase();

    const categorias = [
      'supermercado',
      'restaurante',
      'vestuário',
      'vestuario',
      'saúde',
      'saude',
      'serviços',
      'servicos',
      'eletronicos',
      'eletrônicos',
      'hotel',
      'lazer',
      'health',
      'money',
      'supermarket',
      'outros',
    ];

    for (final categoria in categorias) {
      if (minusculo.contains(categoria)) {
        return categoria;
      }
    }

    return '';
  }

  static String retirarCategoriaECidade(
    String texto,
  ) {
    /*
      O texto extraído costuma terminar assim:

      416,58restaurante SAO PEDRO
      52,28vestuário SAO PAULO

      Esta função é usada apenas para limpar
      informações que ficaram anexadas.
    */

    final categorias = RegExp(
      r'(restaurante|supermercado|vestuário|vestuario|'
      r'saúde|saude|serviços|servicos|outros|lazer|'
      r'eletronicos|eletrônicos|hotel|health|money|'
      r'supermarket)',
      caseSensitive: false,
    );

    final match = categorias.firstMatch(texto);

    if (match == null) {
      return texto.trim();
    }

    return texto.substring(0, match.start).trim();
  }

  static ResultadoFatura processar(String textoOriginal) {
    final texto = textoOriginal
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    // -------------------------------
    // TOTAIS INFORMADOS PELO ITAÚ
    // -------------------------------

    final totalFatura = procurarValor(
      texto,
      RegExp(
        r'Total desta fatura([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalCartao = procurarValor(
      texto,
      RegExp(
        r'Lançamentos no cartão([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalInternacional = procurarValor(
      texto,
      RegExp(
        r'Total lançamentos\s*inter\.\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalServicos = procurarValor(
      texto,
      RegExp(
        r'Lançamentos produtos e serviços'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final lancamentos = <Lancamento>[];

    // ==========================================
    // 1 - COMPRAS E SAQUES
    // ==========================================

    final inicioCompras =
        texto.indexOf('Lançamentos: compras e saques');

    final fimCompras =
        texto.indexOf('Lançamentos no cartão');

    if (inicioCompras >= 0 &&
        fimCompras > inicioCompras) {
      final secaoCompras = texto.substring(
        inicioCompras,
        fimCompras,
      );

      /*
        Cada lançamento começa por DD/MM.
        O próximo DD/MM delimita o anterior.
      */

      final datas = RegExp(
        r'\d{2}/\d{2}',
      ).allMatches(secaoCompras).toList();

      for (int i = 0; i < datas.length; i++) {
        final atual = datas[i];

        final inicio = atual.start;

        final fim = i + 1 < datas.length
            ? datas[i + 1].start
            : secaoCompras.length;

        var bloco =
            secaoCompras.substring(inicio, fim);

        final data =
            bloco.substring(0, 5);

        bloco = bloco.substring(5);

        // Valor seguido pela categoria.
        final valorCategoria = RegExp(
          r'(-?[\d\.]+,\d{2})'
          r'(restaurante|supermercado|vestuário|vestuario|'
          r'saúde|saude|serviços|servicos|outros|lazer|'
          r'eletronicos|eletrônicos|hotel|health|money|'
          r'supermarket)',
          caseSensitive: false,
        ).firstMatch(bloco);

        if (valorCategoria == null) {
          continue;
        }

        final valor =
            moeda(valorCategoria.group(1)!);

        final categoria =
            valorCategoria.group(2) ?? '';

        var descricaoComParcela = bloco.substring(
          0,
          valorCategoria.start,
        );

        descricaoComParcela =
            limparDescricao(descricaoComParcela);

        int? parcelaAtual;
        int? totalParcelas;

        final parcela = RegExp(
          r'\s(\d{2})/(\d{2})$',
        ).firstMatch(descricaoComParcela);

        if (parcela != null) {
          parcelaAtual =
              int.tryParse(parcela.group(1)!);

          totalParcelas =
              int.tryParse(parcela.group(2)!);

          descricaoComParcela =
              descricaoComParcela
                  .substring(0, parcela.start)
                  .trim();
        }

        final descricao =
            retirarCategoriaECidade(
          descricaoComParcela,
        );

        if (descricao.isEmpty) {
          continue;
        }

        lancamentos.add(
          Lancamento(
            data: data,
            descricao: descricao,
            categoria: categoria,
            valor: valor,
            parcelaAtual: parcelaAtual,
            totalParcelas: totalParcelas,
            tipo: parcelaAtual != null
                ? 'Parcelada'
                : 'À vista',
          ),
        );
      }
    }

    // ==========================================
    // 2 - TRANSAÇÕES INTERNACIONAIS
    // ==========================================

    final inicioInternacional =
        texto.indexOf('Lançamentos internacionais');

    final fimInternacional =
        texto.indexOf('Lançamentos: produtos e serviços');

    if (inicioInternacional >= 0 &&
        fimInternacional > inicioInternacional) {
      final secao = texto.substring(
        inicioInternacional,
        fimInternacional,
      );

      /*
        Na fatura de teste:
        compra internacional = R$ 106,12
        IOF = R$ 3,71
      */

      final totalTransacoes = procurarValor(
        secao,
        RegExp(
          r'Total transações inter\. em R\$'
          r'([\d\.]+,\d{2})',
          caseSensitive: false,
        ),
      );

      final iof = procurarValor(
        secao,
        RegExp(
          r'Repasse de IOF em R\$'
          r'([\d\.]+,\d{2})',
          caseSensitive: false,
        ),
      );

      final compra = RegExp(
        r'(\d{2}/\d{2})'
        r'(.+?)'
        r'([\d\.]+,\d{2})'
        r'BRL',
        caseSensitive: false,
      ).firstMatch(secao);

      if (totalTransacoes != null) {
        String descricao = 'Compra internacional';
        String data = '';

        if (compra != null) {
          data = compra.group(1) ?? '';
          descricao =
              limparDescricao(compra.group(2) ?? '');

          if (descricao.isEmpty) {
            descricao = 'Compra internacional';
          }
        }

        lancamentos.add(
          Lancamento(
            data: data,
            descricao: descricao,
            categoria: 'Internacional',
            valor: totalTransacoes,
            tipo: 'Internacional',
          ),
        );
      }

      if (iof != null) {
        lancamentos.add(
          Lancamento(
            data: '',
            descricao:
                'Repasse de IOF - transação internacional',
            categoria: 'Encargos',
            valor: iof,
            tipo: 'Encargo / IOF',
          ),
        );
      }
    }

    // ==========================================
    // 3 - PRODUTOS E SERVIÇOS
    // ==========================================

    final inicioServicos =
        texto.indexOf('Lançamentos: produtos e serviços');

    final fimServicos =
        texto.indexOf('Total dos lançamentos atuais');

    if (inicioServicos >= 0 &&
        fimServicos > inicioServicos) {
      final secao = texto.substring(
        inicioServicos,
        fimServicos,
      );

      /*
        Exemplo real:

        03/08Mensalidade - Plano do105,00
        Anuidade Diferenciada
        30/08Redução Mensalidade - P-52,50
      */

      final datas = RegExp(
        r'\d{2}/\d{2}',
      ).allMatches(secao).toList();

      for (int i = 0; i < datas.length; i++) {
        final atual = datas[i];

        final inicio = atual.start;

        final fim = i + 1 < datas.length
            ? datas[i + 1].start
            : secao.length;

        var bloco =
            secao.substring(inicio, fim);

        final data =
            bloco.substring(0, 5);

        bloco = bloco.substring(5);

        final valorMatch = RegExp(
          r'(-?[\d\.]+,\d{2})',
        ).firstMatch(bloco);

        if (valorMatch == null) {
          continue;
        }

        final valor =
            moeda(valorMatch.group(1)!);

        var descricao = bloco.substring(
          0,
          valorMatch.start,
        );

        descricao =
            limparDescricao(descricao);

        if (descricao.isEmpty) {
          descricao =
              'Produto/serviço Itaú';
        }

        lancamentos.add(
          Lancamento(
            data: data,
            descricao: descricao,
            categoria:
                'Produtos e serviços',
            valor: valor,
            tipo:
                'Produto/Serviço',
          ),
        );
      }
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado: totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado:
          totalServicos,
      lancamentos: lancamentos,
    );
  }
}

class ConferidorApp extends StatelessWidget {
  const ConferidorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Conferidor de Faturas',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool processando = false;

  String status =
      'Selecione uma fatura Itaú em PDF.';

  String? nomeArquivo;

  ResultadoFatura? resultado;

  Future<void> selecionarFatura() async {
    try {
      setState(() {
        processando = true;
        resultado = null;
        status = 'Selecionando fatura...';
      });

      final escolha =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (escolha == null) {
        setState(() {
          processando = false;
          status = 'Seleção cancelada.';
        });
        return;
      }

      final arquivo = escolha.files.single;

      if (arquivo.path == null) {
        throw Exception(
          'Não foi possível acessar o PDF.',
        );
      }

      nomeArquivo = arquivo.name;

      setState(() {
        status =
            'Lendo e analisando a fatura...';
      });

      final bytes =
          await File(arquivo.path!)
              .readAsBytes();

      final documento =
          PdfDocument(inputBytes: bytes);

      final texto =
          PdfTextExtractor(documento)
              .extractText();

      documento.dispose();

      if (texto.trim().isEmpty) {
        throw Exception(
          'Não foi possível extrair texto '
          'do PDF.',
        );
      }

      final analise =
          ParserItau.processar(texto);

      setState(() {
        resultado = analise;
        processando = false;

        if (analise.conciliada) {
          status =
              'Fatura processada e conferida.';
        } else {
          status =
              'Fatura processada. '
              'Confira a diferença abaixo.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;
        status = 'Erro:\n$e';
      });
    }
  }

  String dinheiro(double valor) {
    final sinal =
        valor < 0 ? '-' : '';

    final absoluto = valor.abs();

    final partes =
        absoluto.toStringAsFixed(2).split('.');

    var inteiro = partes[0];

    final buffer = StringBuffer();

    for (int i = 0;
        i < inteiro.length;
        i++) {
      final restante =
          inteiro.length - i;

      buffer.write(inteiro[i]);

      if (restante > 1 &&
          restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${sinal}R\$ '
        '${buffer.toString()},${partes[1]}';
  }

  Widget linhaResumo(
    String titulo,
    String valor,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = resultado;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Conferidor de Faturas',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.credit_card,
            size: 70,
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: processando
                ? null
                : selecionarFatura,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar fatura PDF',
            ),
          ),

          const SizedBox(height: 16),

          if (processando)
            const Center(
              child:
                  CircularProgressIndicator(),
            ),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Text(status),
            ),
          ),

          if (nomeArquivo != null)
            Padding(
              padding:
                  const EdgeInsets.only(
                top: 8,
              ),
              child: Text(
                'Arquivo: $nomeArquivo',
                style: const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

          if (r != null) ...[
            const SizedBox(height: 24),

            const Text(
              'Conferência',
              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  children: [
                    linhaResumo(
                      'Total da fatura',
                      r.totalFatura == null
                          ? 'Não identificado'
                          : dinheiro(
                              r.totalFatura!,
                            ),
                    ),

                    linhaResumo(
                      'Soma dos lançamentos',
                      dinheiro(r.soma),
                    ),

                    linhaResumo(
                      'Diferença',
                      r.diferenca == null
                          ? 'Não calculada'
                          : dinheiro(
                              r.diferenca!,
                            ),
                    ),

                    linhaResumo(
                      'Lançamentos',
                      '${r.lancamentos.length}',
                    ),

                    linhaResumo(
                      'Compras parceladas',
                      '${r.quantidadeParceladas}',
                    ),

                    const Divider(),

                    if (r.totalCartaoInformado !=
                        null)
                      linhaResumo(
                        'Cartão informado pelo Itaú',
                        dinheiro(
                          r.totalCartaoInformado!,
                        ),
                      ),

                    if (r.totalInternacionalInformado !=
                        null)
                      linhaResumo(
                        'Internacional informado',
                        dinheiro(
                          r.totalInternacionalInformado!,
                        ),
                      ),

                    if (r.totalServicosInformado !=
                        null)
                      linhaResumo(
                        'Produtos/serviços informado',
                        dinheiro(
                          r.totalServicosInformado!,
                        ),
                      ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(
                          r.conciliada
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: r.conciliada
                              ? Colors.green
                              : Colors.orange,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            r.conciliada
                                ? 'Fatura conciliada'
                                : 'Conferência pendente',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Lançamentos encontrados',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            ...r.lancamentos.map(
              (item) {
                String detalhe =
                    '${item.data} • '
                    '${item.tipo}';

                if (item.parcelada) {
                  detalhe +=
                      ' • '
                      '${item.parcelaAtual}'
                      '/'
                      '${item.totalParcelas}';
                }

                if (item
                    .categoria.isNotEmpty) {
                  detalhe +=
                      '\n${item.categoria}';
                }

                return Card(
                  child: ListTile(
                    title:
                        Text(item.descricao),
                    subtitle:
                        Text(detalhe),
                    trailing: Text(
                      dinheiro(item.valor),
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 30),

            if (!r.conciliada)
              const Card(
                child: Padding(
                  padding:
                      EdgeInsets.all(16),
                  child: Text(
                    'O Excel ainda não será '
                    'liberado porque a soma '
                    'precisa coincidir exatamente '
                    'com o total da fatura.',
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              ),

            if (r.conciliada)
              const Card(
                child: Padding(
                  padding:
                      EdgeInsets.all(16),
                  child: Text(
                    '✓ Conciliação concluída. '
                    'A próxima versão habilitará '
                    'a exportação do Excel.',
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
