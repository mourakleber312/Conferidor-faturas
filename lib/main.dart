import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const ConferidorApp());
}

// ============================================================
// MODELOS
// ============================================================

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
    if (totalFatura == null) {
      return null;
    }

    return totalFatura! - soma;
  }

  int get quantidadeParceladas {
    return lancamentos
        .where((item) => item.parcelada)
        .length;
  }

  bool get conciliada {
    if (diferenca == null) {
      return false;
    }

    return diferenca!.abs() < 0.01;
  }
}

// ============================================================
// PARSER ITAÚ
// ============================================================

class ParserItau {
  static double moedaParaDouble(String valor) {
    var texto = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    bool negativo = false;

    if (texto.startsWith('-')) {
      negativo = true;
      texto = texto.substring(1);
    }

    texto = texto
        .replaceAll('.', '')
        .replaceAll(',', '.');

    final numero =
        double.tryParse(texto) ?? 0.0;

    return negativo ? -numero : numero;
  }

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? procurarValor(
    String texto,
    RegExp expressao,
  ) {
    final match = expressao.firstMatch(texto);

    if (match == null ||
        match.group(1) == null) {
      return null;
    }

    return moedaParaDouble(
      match.group(1)!,
    );
  }

  static String normalizarCategoria(
    String categoria,
  ) {
    final c = categoria
        .trim()
        .toLowerCase();

    switch (c) {
      case 'vestuario':
        return 'vestuário';

      case 'saude':
        return 'saúde';

      case 'servicos':
        return 'serviços';

      case 'eletronicos':
        return 'eletrônicos';

      case 'supermarket':
        return 'supermercado';

      case 'health':
        return 'saúde';

      case 'money':
        return 'serviços';

      case 'hotel':
        return 'hotel';

      default:
        return c;
    }
  }

  // ==========================================================
  // COMPRAS E SAQUES
  // ==========================================================

  static List<Lancamento> lerCompras(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final inicio =
        texto.indexOf(
      'Lançamentos: compras e saques',
    );

    final fim =
        texto.indexOf(
      'Lançamentos no cartão',
    );

    if (inicio < 0 ||
        fim <= inicio) {
      return resultado;
    }

    var secao = texto.substring(
      inicio,
      fim,
    );

    // Remove cabeçalhos repetidos.
    secao = secao.replaceAll(
      RegExp(
        r'Lançamentos:\s*compras\s*e\s*saques',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll(
      RegExp(
        r'DATAESTABELECIMENTOVALOR\s*EM\s*R\$',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll(
      'continua...',
      '',
    );

    secao = secao
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    /*
      IMPORTANTE

      Primeiro procuramos compras PARCELADAS.

      Exemplo:

      25/04JIM.COM* RIZZO 05/12416,58restaurante

      Assim 05/12 não é confundido com uma nova data.
    */

    final categorias =
        r'(restaurante|supermercado|vestuário|vestuario|'
        r'saúde|saude|serviços|servicos|outros|lazer|'
        r'eletronicos|eletrônicos|hotel|health|money|'
        r'supermarket)';

    final regexLancamento = RegExp(
      r'(\d{2}/\d{2})'
      r'(.+?)'
      r'(?:\s(\d{2})/(\d{2}))?'
      r'(-?[\d\.]+,\d{2})'
      + categorias,
      caseSensitive: false,
    );

    final matches =
        regexLancamento.allMatches(secao);

    for (final match in matches) {
      final data =
          match.group(1) ?? '';

      var descricao =
          match.group(2) ?? '';

      final parcelaAtual =
          int.tryParse(
        match.group(3) ?? '',
      );

      final totalParcelas =
          int.tryParse(
        match.group(4) ?? '',
      );

      final valorTexto =
          match.group(5);

      final categoriaTexto =
          match.group(6);

      if (valorTexto == null ||
          categoriaTexto == null) {
        continue;
      }

      descricao =
          limparEspacos(descricao);

      /*
        Segurança extra:
        se a descrição terminou com parcela porque
        o RegExp colocou a parcela dentro dela,
        retiramos manualmente.
      */

      int? parcelaFinal =
          parcelaAtual;

      int? totalParcelasFinal =
          totalParcelas;

      final parcelaNaDescricao =
          RegExp(
        r'\s(\d{2})/(\d{2})$',
      ).firstMatch(descricao);

      if (parcelaNaDescricao != null) {
        parcelaFinal =
            int.tryParse(
          parcelaNaDescricao.group(1)!,
        );

        totalParcelasFinal =
            int.tryParse(
          parcelaNaDescricao.group(2)!,
        );

        descricao = descricao
            .substring(
              0,
              parcelaNaDescricao.start,
            )
            .trim();
      }

      if (descricao.isEmpty) {
        continue;
      }

      final valor =
          moedaParaDouble(valorTexto);

      final categoria =
          normalizarCategoria(
        categoriaTexto,
      );

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: categoria,
          valor: valor,
          parcelaAtual:
              parcelaFinal,
          totalParcelas:
              totalParcelasFinal,
          tipo:
              parcelaFinal != null &&
                      totalParcelasFinal != null
                  ? 'Parcelada'
                  : 'À vista',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // INTERNACIONAL
  // ==========================================================

  static List<Lancamento>
      lerInternacional(
    String texto,
  ) {
    final resultado =
        <Lancamento>[];

    final inicio =
        texto.indexOf(
      'Lançamentos internacionais',
    );

    final fim =
        texto.indexOf(
      'Lançamentos: produtos e serviços',
    );

    if (inicio < 0 ||
        fim <= inicio) {
      return resultado;
    }

    final secao = texto.substring(
      inicio,
      fim,
    );

    /*
      Exemplo da fatura:

      30/08OPENAI *CHATGPT SUBSCRS106,1299,90BRL19,26
      Dólar de Conversão R$ 5,51
      Total transações inter. em R$106,12
      Repasse de IOF em R$3,71
    */

    final totalCompra =
        procurarValor(
      secao,
      RegExp(
        r'Total transações inter\.\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final iof =
        procurarValor(
      secao,
      RegExp(
        r'Repasse de IOF\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    String data = '';
    String descricao =
        'Compra internacional';

    final dataMatch =
        RegExp(
      r'(\d{2}/\d{2})',
    ).firstMatch(secao);

    if (dataMatch != null) {
      data =
          dataMatch.group(1) ?? '';
    }

    /*
      Captura a descrição entre a data
      e o primeiro valor monetário.
    */

    final descricaoMatch =
        RegExp(
      r'\d{2}/\d{2}'
      r'(.+?)'
      r'[\d\.]+,\d{2}'
      r'[\d\.]+,\d{2}'
      r'BRL',
      caseSensitive: false,
    ).firstMatch(secao);

    if (descricaoMatch != null) {
      var encontrada =
          descricaoMatch.group(1) ?? '';

      /*
        O texto real contém algo como:
        OPENAI *CHATGPT SUBSCRS

        O "S" imediatamente antes do valor
        é o indicador de moeda US$ que ficou
        grudado no texto extraído.
      */

      encontrada =
          limparEspacos(encontrada);

      if (encontrada.endsWith('S')) {
        encontrada = encontrada.substring(
          0,
          encontrada.length - 1,
        );
      }

      encontrada =
          encontrada.trim();

      if (encontrada.isNotEmpty) {
        descricao = encontrada;
      }
    }

    if (totalCompra != null) {
      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria:
              'internacional',
          valor: totalCompra,
          tipo: 'Internacional',
          observacoes:
              'Transação internacional',
        ),
      );
    }

    if (iof != null) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'Repasse de IOF - transação internacional',
          categoria: 'encargos',
          valor: iof,
          tipo: 'Encargo / IOF',
          observacoes:
              'IOF da transação internacional',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PRODUTOS E SERVIÇOS
  // ==========================================================

  static List<Lancamento>
      lerProdutosServicos(
    String texto,
  ) {
    final resultado =
        <Lancamento>[];

    final inicio =
        texto.indexOf(
      'Lançamentos: produtos e serviços',
    );

    final fim =
        texto.indexOf(
      'Total dos lançamentos atuais',
    );

    if (inicio < 0 ||
        fim <= inicio) {
      return resultado;
    }

    var secao =
        texto.substring(
      inicio,
      fim,
    );

    secao = secao.replaceAll(
      RegExp(
        r'Lançamentos:\s*produtos\s*e\s*serviços',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll(
      RegExp(
        r'DATAPRODUTOS/SERVIÇOSVALOR\s*EM\s*R\$',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    final datas =
        RegExp(
      r'\d{2}/\d{2}',
    ).allMatches(secao).toList();

    for (int i = 0;
        i < datas.length;
        i++) {
      final atual = datas[i];

      final inicioBloco =
          atual.start;

      final fimBloco =
          i + 1 < datas.length
              ? datas[i + 1].start
              : secao.length;

      var bloco =
          secao.substring(
        inicioBloco,
        fimBloco,
      );

      final data =
          bloco.substring(0, 5);

      bloco =
          bloco.substring(5);

      final valorMatch =
          RegExp(
        r'(-?[\d\.]+,\d{2})',
      ).firstMatch(bloco);

      if (valorMatch == null) {
        continue;
      }

      var descricao =
          bloco.substring(
        0,
        valorMatch.start,
      );

      descricao =
          limparEspacos(descricao);

      if (descricao.isEmpty) {
        descricao =
            'Produto/serviço Itaú';
      }

      final valor =
          moedaParaDouble(
        valorMatch.group(1)!,
      );

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria:
              'produtos e serviços',
          valor: valor,
          tipo: 'Produto/Serviço',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PROCESSAMENTO COMPLETO
  // ==========================================================

  static ResultadoFatura processar(
    String textoOriginal,
  ) {
    /*
      Mantemos o conteúdo, mas retiramos
      quebras de linha para reproduzir
      corretamente a estrutura extraída
      pelo PDF do Itaú.
    */

    final texto = textoOriginal
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    final totalFatura =
        procurarValor(
      texto,
      RegExp(
        r'Total desta fatura'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalCartao =
        procurarValor(
      texto,
      RegExp(
        r'Lançamentos no cartão'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalInternacional =
        procurarValor(
      texto,
      RegExp(
        r'Total lançamentos\s*inter\.\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalServicos =
        procurarValor(
      texto,
      RegExp(
        r'Lançamentos produtos e serviços'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final lancamentos =
        <Lancamento>[];

    lancamentos.addAll(
      lerCompras(texto),
    );

    lancamentos.addAll(
      lerInternacional(texto),
    );

    lancamentos.addAll(
      lerProdutosServicos(texto),
    );

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado:
          totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado:
          totalServicos,
      lancamentos: lancamentos,
    );
  }
}

// ============================================================
// APLICATIVO
// ============================================================

class ConferidorApp
    extends StatelessWidget {
  const ConferidorApp({super.key});

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false,
      title:
          'Conferidor de Faturas',
      theme: ThemeData(
        colorSchemeSeed:
            Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage
    extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState
    extends State<HomePage> {
  bool processando = false;

  String status =
      'Selecione uma fatura Itaú em PDF.';

  String? nomeArquivo;

  ResultadoFatura? resultado;

  Future<void>
      selecionarFatura() async {
    try {
      setState(() {
        processando = true;
        resultado = null;
        nomeArquivo = null;

        status =
            'Selecionando fatura...';
      });

      final escolha =
          await FilePicker.platform
              .pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (escolha == null) {
        setState(() {
          processando = false;
          status =
              'Seleção cancelada.';
        });

        return;
      }

      final arquivo =
          escolha.files.single;

      if (arquivo.path == null) {
        throw Exception(
          'Não foi possível acessar o PDF.',
        );
      }

      setState(() {
        nomeArquivo =
            arquivo.name;

        status =
            'Lendo e conferindo a fatura...';
      });

      final bytes =
          await File(
        arquivo.path!,
      ).readAsBytes();

      final documento =
          PdfDocument(
        inputBytes: bytes,
      );

      final texto =
          PdfTextExtractor(
        documento,
      ).extractText();

      documento.dispose();

      if (texto.trim().isEmpty) {
        throw Exception(
          'Não foi possível extrair '
          'texto do PDF.',
        );
      }

      final analise =
          ParserItau.processar(
        texto,
      );

      setState(() {
        resultado = analise;
        processando = false;

        if (analise.conciliada) {
          status =
              'Fatura processada e conferida.';
        } else {
          status =
              'Fatura processada. '
              'Ainda existe diferença '
              'na conferência.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;

        status =
            'Erro ao processar:\n$e';
      });
    }
  }

  String dinheiro(
    double valor,
  ) {
    final sinal =
        valor < 0 ? '-' : '';

    final absoluto =
        valor.abs();

    final partes =
        absoluto
            .toStringAsFixed(2)
            .split('.');

    final inteiro =
        partes[0];

    final buffer =
        StringBuffer();

    for (int i = 0;
        i < inteiro.length;
        i++) {
      final restante =
          inteiro.length - i;

      buffer.write(
        inteiro[i],
      );

      if (restante > 1 &&
          restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${sinal}R\$ '
        '${buffer.toString()},'
        '${partes[1]}';
  }

  Widget linhaResumo(
    String titulo,
    String valor,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo),
          ),
          const SizedBox(width: 10),
          Text(
            valor,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
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
            size: 65,
          ),

          const SizedBox(
            height: 18,
          ),

          FilledButton.icon(
            onPressed:
                processando
                    ? null
                    : selecionarFatura,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar fatura PDF',
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          if (processando)
            const Center(
              child:
                  CircularProgressIndicator(),
            ),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
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
                'Arquivo: '
                '$nomeArquivo',
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

          if (r != null) ...[
            const SizedBox(
              height: 24,
            ),

            const Text(
              'Conferência',
              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

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
                      r.totalFatura ==
                              null
                          ? 'Não identificado'
                          : dinheiro(
                              r.totalFatura!,
                            ),
                    ),

                    linhaResumo(
                      'Soma dos lançamentos',
                      dinheiro(
                        r.soma,
                      ),
                    ),

                    linhaResumo(
                      'Diferença',
                      r.diferenca ==
                              null
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

                    const SizedBox(
                      height: 12,
                    ),

                    Row(
                      children: [
                        Icon(
                          r.conciliada
                              ? Icons
                                  .check_circle
                              : Icons
                                  .warning_amber,
                          color:
                              r.conciliada
                                  ? Colors.green
                                  : Colors
                                      .orange,
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        Expanded(
                          child: Text(
                            r.conciliada
                                ? 'Fatura conciliada'
                                : 'Conferência pendente',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            const Text(
              'Lançamentos encontrados',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            ...r.lancamentos.map(
              (item) {
                var detalhe =
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
                    .categoria
                    .isNotEmpty) {
                  detalhe +=
                      '\n'
                      '${item.categoria}';
                }

                return Card(
                  child: ListTile(
                    title: Text(
                      item.descricao,
                    ),
                    subtitle: Text(
                      detalhe,
                    ),
                    trailing: Text(
                      dinheiro(
                        item.valor,
                      ),
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

            const SizedBox(
              height: 25,
            ),

            if (r.conciliada)
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    18,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons
                            .verified,
                        color:
                            Colors.green,
                        size: 40,
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      const Text(
                        'Fatura conciliada',
                        style:
                            TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        'A soma dos '
                        '${r.lancamentos.length} '
                        'lançamentos é igual '
                        'ao total da fatura.',
                        textAlign:
                            TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              const Card(
                child: Padding(
                  padding:
                      EdgeInsets.all(
                    18,
                  ),
                  child: Text(
                    'O Excel continua '
                    'bloqueado até que a '
                    'diferença seja '
                    'R\$ 0,00.',
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              ),
          ],

          const SizedBox(
            height: 40,
          ),
        ],
      ),
    );
  }
}
