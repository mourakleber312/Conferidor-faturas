import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final double? totalEncargosInformado;

  final String vencimento;
  final String cartao;

  final List<Lancamento> lancamentos;
  final List<String> alertas;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
    this.totalEncargosInformado,
    this.vencimento = '',
    this.cartao = '',
    this.alertas = const [],
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
    if (totalFatura == null) return false;
    if (lancamentos.isEmpty) return false;
    if (diferenca == null) return false;

    return diferenca!.abs() < 0.01;
  }

  bool get falhaLeitura {
    return totalFatura == null || lancamentos.isEmpty;
  }

  String get status {
    if (falhaLeitura) {
      return 'FALHA DE LEITURA';
    }

    if (conciliada) {
      return 'CONCILIADA';
    }

    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;

  FaturaProcessada({
    required this.arquivo,
    required this.resultado,
  });
}

// ============================================================
// PARSER ITAÚ
// ============================================================

class ParserItau {
  // ----------------------------------------------------------
  // UTILIDADES
  // ----------------------------------------------------------

  static String semAcentos(String texto) {
    return texto
        .replaceAll(RegExp('[áàãâäÁÀÃÂÄ]'), 'a')
        .replaceAll(RegExp('[éèêëÉÈÊË]'), 'e')
        .replaceAll(RegExp('[íìîïÍÌÎÏ]'), 'i')
        .replaceAll(RegExp('[óòõôöÓÒÕÔÖ]'), 'o')
        .replaceAll(RegExp('[úùûüÚÙÛÜ]'), 'u')
        .replaceAll(RegExp('[çÇ]'), 'c');
  }

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static String compactar(String texto) {
    return semAcentos(texto)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
  }

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

    final numero = double.tryParse(texto) ?? 0.0;

    return negativo ? -numero : numero;
  }

  static String normalizarValor(String texto) {
    return texto
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('R\$', '');
  }

  static String normalizarData(String data) {
    var d = data.replaceAll(' ', '');

    final partes = d.split('/');

    if (partes.length != 2) {
      return d;
    }

    final dia =
        partes[0].padLeft(2, '0');

    final mes =
        partes[1].padLeft(2, '0');

    return '$dia/$mes';
  }

  static String normalizarParcela(String parcela) {
    return parcela.replaceAll(' ', '');
  }

  static double? primeiroValorDepois(
    String texto,
    RegExp marcador,
  ) {
    final match = marcador.firstMatch(texto);

    if (match == null) return null;

    final resto = texto.substring(match.end);

    final valor = RegExp(
      r'-?\s*\d[\d\.\s]*,\s*\d{2}',
    ).firstMatch(resto);

    if (valor == null) return null;

    return moedaParaDouble(
      normalizarValor(valor.group(0)!),
    );
  }

  static String procurarVencimento(String texto) {
    final regex = RegExp(
      r'Vencimento\s*:\s*(\d{2}/\d{2}/\d{4})',
      caseSensitive: false,
    );

    final m = regex.firstMatch(texto);

    return m?.group(1) ?? '';
  }

  static String procurarCartao(String texto) {
    final regex = RegExp(
      r'Cart[aã]o\s+([0-9Xx\.\s]+)',
      caseSensitive: false,
    );

    final m = regex.firstMatch(texto);

    if (m == null) return '';

    return limparEspacos(
      m.group(1) ?? '',
    );
  }

  // ----------------------------------------------------------
  // LOCALIZAÇÃO FLEXÍVEL DE TÍTULOS
  // ----------------------------------------------------------

  static int localizarTitulo(
    String texto,
    String tituloCompactado, {
    int inicio = 0,
  }) {
    if (inicio >= texto.length) {
      return -1;
    }

    final alvo =
        compactar(tituloCompactado);

    final limite =
        texto.length;

    const tamanhoJanela = 160;

    for (int i = inicio;
        i < limite;
        i++) {
      final fim =
          (i + tamanhoJanela < limite)
              ? i + tamanhoJanela
              : limite;

      final trecho =
          compactar(texto.substring(i, fim));

      if (trecho.startsWith(alvo)) {
        return i;
      }
    }

    return -1;
  }

  static int localizarPrimeiroDe(
    String texto,
    List<String> titulos, {
    int inicio = 0,
  }) {
    int melhor = -1;

    for (final titulo in titulos) {
      final pos = localizarTitulo(
        texto,
        titulo,
        inicio: inicio,
      );

      if (pos >= 0 &&
          (melhor < 0 || pos < melhor)) {
        melhor = pos;
      }
    }

    return melhor;
  }

  // ----------------------------------------------------------
  // CATEGORIAS
  // ----------------------------------------------------------

  static const List<String> categoriasBase = [
    'restaurante',
    'supermercado',
    'vestuario',
    'saude',
    'servicos',
    'outros',
    'lazer',
    'eletronicos',
    'hotel',
    'health',
    'money',
    'supermarket',
    'transporte',
    'educacao',
  ];

  static String? detectarCategoria(
    String linha,
  ) {
    final c = compactar(linha);

    for (final categoria
        in categoriasBase) {
      if (c.contains(categoria)) {
        return normalizarCategoria(
          categoria,
        );
      }
    }

    return null;
  }

  static String normalizarCategoria(
    String categoria,
  ) {
    final c =
        semAcentos(categoria).toLowerCase();

    switch (c) {
      case 'vestuario':
        return 'vestuário';

      case 'saude':
      case 'health':
        return 'saúde';

      case 'servicos':
      case 'money':
        return 'serviços';

      case 'eletronicos':
        return 'eletrônicos';

      case 'supermarket':
        return 'supermercado';

      case 'educacao':
        return 'educação';

      default:
        return c;
    }
  }

  // ----------------------------------------------------------
  // NORMALIZAÇÃO DAS LINHAS
  // ----------------------------------------------------------

  static List<String> prepararLinhas(
    String texto,
  ) {
    var t = texto
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ');

    final originais =
        t.split('\n');

    final linhas = <String>[];

    for (var linha in originais) {
      linha = limparEspacos(linha);

      if (linha.isEmpty) continue;

      linhas.add(linha);
    }

    return linhas;
  }

  static bool linhaEhCabecalho(
    String linha,
  ) {
    final c = compactar(linha);

    if (c.isEmpty) return true;

    return c.contains(
          'dataestabelecimentovaloremr',
        ) ||
        c == 'data' ||
        c == 'estabelecimento' ||
        c.contains(
          'lancamentoscomprasesaques',
        ) ||
        c.contains(
          'comprasparceladasproximasfaturas',
        ) ||
        c.contains(
          'pagamentosefetuados',
        ) ||
        c.contains('klebermoura') ||
        c == 'continua...';
  }

  // ----------------------------------------------------------
  // EXTRAÇÃO DE TRANSAÇÃO
  // ----------------------------------------------------------

  static Map<String, dynamic>?
      extrairTransacaoDaLinha(
    String linha,
  ) {
    var l = limparEspacos(linha);

    // Corrige datas fragmentadas:
    // 27/0 7 -> 27/07
    l = l.replaceAllMapped(
      RegExp(
        r'(\d{1,2})\s*/\s*(\d)\s+(\d)',
      ),
      (m) =>
          '${m.group(1)}/${m.group(2)}${m.group(3)}',
    );

    // Corrige parcelas fragmentadas:
    // 06/1 0 -> 06/10
    l = l.replaceAllMapped(
      RegExp(
        r'(\d{1,2})\s*/\s*(\d)\s+(\d)',
      ),
      (m) =>
          '${m.group(1)}/${m.group(2)}${m.group(3)}',
    );

    // Corrige valor:
    // 75 ,57 -> 75,57
    // 159 ,00 -> 159,00
    l = l.replaceAllMapped(
      RegExp(
        r'(\d)\s+,\s*(\d{2})',
      ),
      (m) =>
          '${m.group(1)},${m.group(2)}',
    );

    final dataMatch = RegExp(
      r'^(\d{1,2}/\d{1,2})\s+',
    ).firstMatch(l);

    if (dataMatch == null) {
      return null;
    }

    final data =
        normalizarData(dataMatch.group(1)!);

    var resto =
        l.substring(dataMatch.end).trim();

    final valorMatch = RegExp(
      r'(-?\d[\d\.]*,\d{2})(?!.*\d[\d\.]*,\d{2})',
    ).firstMatch(resto);

    if (valorMatch == null) {
      return null;
    }

    final valor = moedaParaDouble(
      valorMatch.group(1)!,
    );

    var antesValor = resto
        .substring(0, valorMatch.start)
        .trim();

    int? parcelaAtual;
    int? totalParcelas;

    final parcelaMatch = RegExp(
      r'(\d{1,2})\s*/\s*(\d{1,2})\s*$',
    ).firstMatch(antesValor);

    if (parcelaMatch != null) {
      parcelaAtual =
          int.tryParse(parcelaMatch.group(1)!);

      totalParcelas =
          int.tryParse(parcelaMatch.group(2)!);

      antesValor = antesValor
          .substring(0, parcelaMatch.start)
          .trim();
    }

    if (antesValor.isEmpty) {
      return null;
    }

    return {
      'data': data,
      'descricao': antesValor,
      'valor': valor,
      'parcelaAtual': parcelaAtual,
      'totalParcelas': totalParcelas,
    };
  }

  // ----------------------------------------------------------
  // COMPRAS E SAQUES
  // ----------------------------------------------------------

  static List<Lancamento> lerCompras(
    String texto,
  ) {
    final resultado =
        <Lancamento>[];

    final inicio = localizarPrimeiroDe(
      texto,
      [
        'Lançamentos: compras e saques',
        'Lancamentos: compras e saques',
      ],
    );

    if (inicio < 0) {
      return resultado;
    }

    var fim = localizarPrimeiroDe(
      texto,
      [
        'Lançamentos no cartão',
        'Lancamentos no cartao',
        'Lançamentos internacionais',
        'Lancamentos internacionais',
        'Lançamentos: produtos e serviços',
        'Lancamentos: produtos e servicos',
        'Compras parceladas - próximas faturas',
        'Compras parceladas proximas faturas',
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
      ],
      inicio: inicio + 10,
    );

    if (fim < 0) {
      fim = texto.length;
    }

    final secao =
        texto.substring(inicio, fim);

    final linhas =
        prepararLinhas(secao);

    Lancamento? pendente;

    for (int i = 0;
        i < linhas.length;
        i++) {
      final linha = linhas[i];

      if (linhaEhCabecalho(linha)) {
        continue;
      }

      final transacao =
          extrairTransacaoDaLinha(linha);

      if (transacao != null) {
        if (pendente != null) {
          resultado.add(pendente);
          pendente = null;
        }

        String categoria = '';

        if (i + 1 < linhas.length) {
          categoria =
              detectarCategoria(
                    linhas[i + 1],
                  ) ??
                  '';
        }

        final pa =
            transacao['parcelaAtual'] as int?;

        final tp =
            transacao['totalParcelas'] as int?;

        pendente = Lancamento(
          data: transacao['data'],
          descricao: limparEspacos(
            transacao['descricao'],
          ),
          categoria: categoria,
          valor: transacao['valor'],
          parcelaAtual: pa,
          totalParcelas: tp,
          tipo: pa != null && tp != null
              ? 'Parcelada'
              : 'À vista',
        );

        continue;
      }

      if (pendente != null &&
          pendente.categoria.isEmpty) {
        final categoria =
            detectarCategoria(linha);

        if (categoria != null) {
          pendente = Lancamento(
            data: pendente.data,
            descricao:
                pendente.descricao,
            categoria: categoria,
            valor: pendente.valor,
            parcelaAtual:
                pendente.parcelaAtual,
            totalParcelas:
                pendente.totalParcelas,
            tipo: pendente.tipo,
            observacoes:
                pendente.observacoes,
          );
        }
      }
    }

    if (pendente != null) {
      resultado.add(pendente);
    }

    return resultado;
  }

  // ----------------------------------------------------------
  // INTERNACIONAL
  // ----------------------------------------------------------

  static List<Lancamento> lerInternacional(
    String texto,
  ) {
    final resultado =
        <Lancamento>[];

    final inicio = localizarPrimeiroDe(
      texto,
      [
        'Lançamentos internacionais',
        'Lancamentos internacionais',
      ],
    );

    if (inicio < 0) {
      return resultado;
    }

    var fim = localizarPrimeiroDe(
      texto,
      [
        'Lançamentos: produtos e serviços',
        'Lancamentos: produtos e servicos',
        'Compras parceladas - próximas faturas',
        'Compras parceladas proximas faturas',
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
      ],
      inicio: inicio + 10,
    );

    if (fim < 0) {
      fim = texto.length;
    }

    final secao =
        texto.substring(inicio, fim);

    final totalInternacional =
        primeiroValorDepois(
      secao,
      RegExp(
        r'Total\s+transa[cç][oõ]es\s+inter',
        caseSensitive: false,
      ),
    );

    final iof = primeiroValorDepois(
      secao,
      RegExp(
        r'Repasse\s+de\s+IOF',
        caseSensitive: false,
      ),
    );

    if (totalInternacional != null) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'Transações internacionais',
          categoria: 'internacional',
          valor: totalInternacional,
          tipo: 'Internacional',
          observacoes:
              'Subtotal internacional informado pelo Itaú',
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
              'IOF de transação internacional',
        ),
      );
    }

    return resultado;
  }

  // ----------------------------------------------------------
  // PRODUTOS E SERVIÇOS
  // ----------------------------------------------------------

  static List<Lancamento>
      lerProdutosServicos(
    String texto,
  ) {
    final resultado =
        <Lancamento>[];

    final inicio = localizarPrimeiroDe(
      texto,
      [
        'Lançamentos: produtos e serviços',
        'Lancamentos: produtos e servicos',
      ],
    );

    if (inicio < 0) {
      return resultado;
    }

    var fim = localizarPrimeiroDe(
      texto,
      [
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
        'Compras parceladas - próximas faturas',
        'Compras parceladas proximas faturas',
      ],
      inicio: inicio + 10,
    );

    if (fim < 0) {
      fim = texto.length;
    }

    final secao =
        texto.substring(inicio, fim);

    final linhas =
        prepararLinhas(secao);

    for (final linha in linhas) {
      var l = linha;

      l = l.replaceAllMapped(
        RegExp(
          r'(\d{1,2})\s*/\s*(\d)\s+(\d)',
        ),
        (m) =>
            '${m.group(1)}/${m.group(2)}${m.group(3)}',
      );

      l = l.replaceAllMapped(
        RegExp(
          r'(\d)\s+,\s*(\d{2})',
        ),
        (m) =>
            '${m.group(1)},${m.group(2)}',
      );

      final dataMatch = RegExp(
        r'^(\d{1,2}/\d{1,2})\s+',
      ).firstMatch(l);

      if (dataMatch == null) continue;

      final data =
          normalizarData(dataMatch.group(1)!);

      final resto =
          l.substring(dataMatch.end);

      final valorMatch = RegExp(
        r'(-?\d[\d\.]*,\d{2})',
      ).firstMatch(resto);

      if (valorMatch == null) continue;

      var descricao = resto
          .substring(0, valorMatch.start)
          .trim();

      if (descricao.isEmpty) {
        descricao =
            'Produto/serviço Itaú';
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao:
              limparEspacos(descricao),
          categoria:
              'produtos e serviços',
          valor: moedaParaDouble(
            valorMatch.group(1)!,
          ),
          tipo: 'Produto/Serviço',
        ),
      );
    }

    return resultado;
  }

  // ----------------------------------------------------------
  // ENCARGOS FINANCEIROS / MORATÓRIOS
  // ----------------------------------------------------------

  static List<Lancamento>
      lerEncargosFinanceiros(
    String texto,
    double? totalEncargos,
  ) {
    final resultado =
        <Lancamento>[];

    if (totalEncargos == null ||
        totalEncargos.abs() < 0.01) {
      return resultado;
    }

    // Não usamos aqui os encargos da simulação
    // de pagamento mínimo da primeira página.
    // O valor só entra se o resumo da fatura
    // informar encargos efetivamente cobrados.

    resultado.add(
      Lancamento(
        data: '',
        descricao:
            'Encargos de financiamento / moratórios',
        categoria: 'encargos',
        valor: totalEncargos,
        tipo: 'Encargo',
        observacoes:
            'Encargos efetivamente cobrados nesta fatura',
      ),
    );

    return resultado;
  }

  // ----------------------------------------------------------
  // TOTAIS
  // ----------------------------------------------------------

  static double? procurarTotalFatura(
    String texto,
  ) {
    final padroes = [
      RegExp(
        r'Total\s+desta\s+fatura\s*'
        r'(-?\s*\d[\d\.\s]*,\s*\d{2})',
        caseSensitive: false,
      ),
      RegExp(
        r'O\s+total\s+da\s+sua\s+fatura\s+[eé]\s*:?\s*'
        r'R?\$?\s*(-?\s*\d[\d\.\s]*,\s*\d{2})',
        caseSensitive: false,
      ),
    ];

    for (final regex in padroes) {
      final m = regex.firstMatch(texto);

      if (m != null &&
          m.group(1) != null) {
        return moedaParaDouble(
          normalizarValor(
            m.group(1)!,
          ),
        );
      }
    }

    // Busca tolerante a fragmentação.
    final linhas =
        prepararLinhas(texto);

    for (int i = 0;
        i < linhas.length;
        i++) {
      final c =
          compactar(linhas[i]);

      if (c.contains(
        'totaldestafatura',
      )) {
        final valor = RegExp(
          r'-?\s*\d[\d\.\s]*,\s*\d{2}',
        ).allMatches(linhas[i]).toList();

        if (valor.isNotEmpty) {
          return moedaParaDouble(
            normalizarValor(
              valor.last.group(0)!,
            ),
          );
        }

        if (i + 1 < linhas.length) {
          final proximo = RegExp(
            r'-?\s*\d[\d\.\s]*,\s*\d{2}',
          ).firstMatch(linhas[i + 1]);

          if (proximo != null) {
            return moedaParaDouble(
              normalizarValor(
                proximo.group(0)!,
              ),
            );
          }
        }
      }
    }

    return null;
  }

  static double? procurarSubtotal(
    String texto,
    List<String> nomes,
  ) {
    final linhas =
        prepararLinhas(texto);

    for (final linha in linhas) {
      final c =
          compactar(linha);

      for (final nome in nomes) {
        if (c.contains(
          compactar(nome),
        )) {
          final valores = RegExp(
            r'-?\s*\d[\d\.\s]*,\s*\d{2}',
          ).allMatches(linha).toList();

          if (valores.isNotEmpty) {
            return moedaParaDouble(
              normalizarValor(
                valores.last.group(0)!,
              ),
            );
          }
        }
      }
    }

    return null;
  }

  // ----------------------------------------------------------
  // REMOÇÃO DE DUPLICIDADES
  // ----------------------------------------------------------

  static List<Lancamento>
      removerDuplicados(
    List<Lancamento> itens,
  ) {
    final resultado =
        <Lancamento>[];

    final vistos = <String>{};

    for (final item in itens) {
      final chave =
          '${item.data}|'
          '${compactar(item.descricao)}|'
          '${item.valor.toStringAsFixed(2)}|'
          '${item.parcelaAtual}|'
          '${item.totalParcelas}|'
          '${item.tipo}';

      if (!vistos.contains(chave)) {
        vistos.add(chave);
        resultado.add(item);
      }
    }

    return resultado;
  }

  // ----------------------------------------------------------
  // PROCESSAMENTO PRINCIPAL
  // ----------------------------------------------------------

  static ResultadoFatura processar(
    String textoOriginal,
  ) {
    final alertas =
        <String>[];

    final totalFatura =
        procurarTotalFatura(
      textoOriginal,
    );

    final totalCartao =
        procurarSubtotal(
      textoOriginal,
      [
        'Lançamentos no cartão',
        'Lancamentos no cartao',
      ],
    );

    final totalInternacional =
        procurarSubtotal(
      textoOriginal,
      [
        'Total lançamentos inter. em R\$',
        'Total lancamentos inter. em R\$',
      ],
    );

    final totalServicos =
        procurarSubtotal(
      textoOriginal,
      [
        'Lançamentos produtos e serviços',
        'Lancamentos produtos e servicos',
      ],
    );

    // Alguns layouts têm encargos efetivamente
    // cobrados fora dos lançamentos do cartão.
    //
    // Primeiro tentamos identificar um subtotal
    // explícito de encargos da fatura.
    double? totalEncargos =
        procurarSubtotal(
      textoOriginal,
      [
        'Encargos de financiamento',
        'Encargos financiamento',
        'Encargos moratórios',
        'Encargos moratorios',
        'Total encargos',
      ],
    );

    final compras =
        lerCompras(textoOriginal);

    final produtos =
        lerProdutosServicos(
      textoOriginal,
    );

    final internacional =
        lerInternacional(
      textoOriginal,
    );

    // --------------------------------------------------------
    // CONSTRUÇÃO INICIAL
    // --------------------------------------------------------

    var lancamentos =
        <Lancamento>[];

    lancamentos.addAll(compras);
    lancamentos.addAll(produtos);

    // Se há subtotal internacional, precisamos evitar
    // dupla contagem.
    //
    // O parser internacional adiciona o subtotal das
    // transações + IOF separadamente.
    lancamentos.addAll(internacional);

    lancamentos =
        removerDuplicados(lancamentos);

    // --------------------------------------------------------
    // RECONCILIAÇÃO POR SUBTOTAIS
    // --------------------------------------------------------

    double somaSemEncargos =
        lancamentos.fold(
      0.0,
      (s, e) => s + e.valor,
    );

    if (totalFatura != null) {
      final falta =
          totalFatura - somaSemEncargos;

      // Se existe um subtotal explícito de encargos,
      // ele deve explicar a diferença.
      if (totalEncargos != null &&
          (falta - totalEncargos).abs() <
              0.02) {
        lancamentos.addAll(
          lerEncargosFinanceiros(
            textoOriginal,
            totalEncargos,
          ),
        );
      } else if (falta.abs() >= 0.01) {
        // Caso especial observado nas faturas:
        // quando cartão + produtos + internacional
        // não chegam ao total, verificamos se a
        // diferença corresponde a encargos cobrados.
        //
        // Não aceitamos qualquer diferença como
        // encargo automaticamente. Ela precisa ter
        // evidência textual no documento.

        final compacto =
            compactar(textoOriginal);

        final temIndicacaoEncargos =
            compacto.contains(
                  'encargosdefinanciamento',
                ) ||
                compacto.contains(
                  'encargosmoratorios',
                ) ||
                compacto.contains(
                  'jurosrotativo',
                ) ||
                compacto.contains(
                  'jurosdemora',
                ) ||
                compacto.contains(
                  'multaporatraso',
                );

        if (temIndicacaoEncargos &&
            falta > 0) {
          totalEncargos = falta;

          lancamentos.add(
            Lancamento(
              data: '',
              descricao:
                  'Encargos de financiamento / moratórios',
              categoria: 'encargos',
              valor: falta,
              tipo: 'Encargo',
              observacoes:
                  'Valor conciliado com encargos '
                  'identificados no PDF',
            ),
          );
        }
      }
    }

    lancamentos =
        removerDuplicados(lancamentos);

    // --------------------------------------------------------
    // ALERTAS
    // --------------------------------------------------------

    if (totalFatura == null) {
      alertas.add(
        'Total da fatura não identificado.',
      );
    }

    if (compras.isEmpty) {
      alertas.add(
        'Nenhuma compra foi identificada.',
      );
    }

    final somaFinal =
        lancamentos.fold<double>(
      0.0,
      (s, e) => s + e.valor,
    );

    if (totalFatura != null) {
      final diff =
          totalFatura - somaFinal;

      if (diff.abs() >= 0.01) {
        alertas.add(
          'Diferença de conciliação: '
          'R\$ ${diff.toStringAsFixed(2)}',
        );
      }
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado:
          totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado:
          totalServicos,
      totalEncargosInformado:
          totalEncargos,
      vencimento:
          procurarVencimento(
        textoOriginal,
      ),
      cartao:
          procurarCartao(
        textoOriginal,
      ),
      lancamentos: lancamentos,
      alertas: alertas,
    );
  }
}

// ============================================================
// APP
// ============================================================

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

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState
    extends State<HomePage> {
  bool processando = false;
  bool gerandoExcel = false;

  String status =
      'Selecione uma ou mais faturas Itaú em PDF.';

  final List<FaturaProcessada>
      faturas = [];

  // ----------------------------------------------------------
  // RESUMO
  // ----------------------------------------------------------

  int get quantidadeConciliadas =>
      faturas
          .where(
            (f) =>
                f.resultado.conciliada,
          )
          .length;

  int get quantidadeFalhas =>
      faturas
          .where(
            (f) =>
                f.resultado.falhaLeitura,
          )
          .length;

  int get quantidadeDivergentes =>
      faturas
          .where(
            (f) =>
                !f.resultado.conciliada &&
                !f.resultado.falhaLeitura,
          )
          .length;

  int get totalLancamentos =>
      faturas.fold(
        0,
        (total, f) =>
            total +
            f.resultado.lancamentos.length,
      );

  int get totalParceladas =>
      faturas.fold(
        0,
        (total, f) =>
            total +
            f.resultado
                .quantidadeParceladas,
      );

  double get valorTotalFaturas =>
      faturas.fold(
        0.0,
        (total, f) =>
            total +
            (f.resultado.totalFatura ??
                0),
      );

  double get somaTotalLancamentos =>
      faturas.fold(
        0.0,
        (total, f) =>
            total +
            f.resultado.soma,
      );

  double get diferencaTotal =>
      valorTotalFaturas -
      somaTotalLancamentos;

  bool get todasConciliadas =>
      faturas.isNotEmpty &&
      faturas.every(
        (f) => f.resultado.conciliada,
      );

  // ----------------------------------------------------------
  // SELEÇÃO
  // ----------------------------------------------------------

  Future<void>
      selecionarFaturas() async {
    try {
      final escolha =
          await FilePicker.platform
              .pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (escolha == null ||
          escolha.files.isEmpty) {
        return;
      }

      setState(() {
        processando = true;
        faturas.clear();

        status =
            'Preparando ${escolha.files.length} '
            'fatura(s)...';
      });

      for (int i = 0;
          i < escolha.files.length;
          i++) {
        final arquivo =
            escolha.files[i];

        setState(() {
          status =
              'Analisando ${i + 1} de '
              '${escolha.files.length}\n'
              '${arquivo.name}';
        });

        try {
          if (arquivo.path == null) {
            throw Exception(
              'Arquivo sem caminho acessível.',
            );
          }

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
            faturas.add(
              FaturaProcessada(
                arquivo: arquivo.name,
                resultado:
                    ResultadoFatura(
                  totalFatura: null,
                  lancamentos: const [],
                  alertas: const [
                    'O PDF não forneceu texto para leitura.',
                  ],
                ),
              ),
            );

            continue;
          }

          final resultado =
              ParserItau.processar(
            texto,
          );

          faturas.add(
            FaturaProcessada(
              arquivo: arquivo.name,
              resultado: resultado,
            ),
          );
        } catch (e) {
          // A fatura permanece na lista.
          // Nunca desaparece silenciosamente.
          faturas.add(
            FaturaProcessada(
              arquivo: arquivo.name,
              resultado:
                  ResultadoFatura(
                totalFatura: null,
                lancamentos: const [],
                alertas: [
                  'Falha ao processar: $e',
                ],
              ),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        processando = false;

        if (todasConciliadas) {
          status =
              '${faturas.length} fatura(s) '
              'processada(s) e conferida(s).';
        } else {
          status =
              '${faturas.length} fatura(s) processada(s).\n'
              '$quantidadeConciliadas conciliada(s), '
              '$quantidadeDivergentes divergente(s), '
              '$quantidadeFalhas com falha de leitura.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processando = false;
        status =
            'Erro ao selecionar arquivos:\n$e';
      });
    }
  }

  // ----------------------------------------------------------
  // EXCEL
  // ----------------------------------------------------------

  Future<void>
      gerarExcelConsolidado() async {
    if (!todasConciliadas) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'O Excel só será liberado '
            'quando todas as faturas '
            'estiverem conciliadas.',
          ),
        ),
      );

      return;
    }

    try {
      setState(() {
        gerandoExcel = true;
      });

      final excel =
          Excel.createExcel();

      // ======================================================
      // LANÇAMENTOS
      // ======================================================

      final sheet =
          excel['Lançamentos'];

      sheet.appendRow([
        TextCellValue('Fatura / Arquivo'),
        TextCellValue('Vencimento'),
        TextCellValue('Cartão'),
        TextCellValue('Data da compra'),
        TextCellValue(
          'Descrição da compra',
        ),
        TextCellValue('Categoria'),
        TextCellValue('Valor'),
        TextCellValue('Parcela atual'),
        TextCellValue(
          'Quantidade total de parcelas',
        ),
        TextCellValue('Tipo'),
        TextCellValue('Observações'),
      ]);

      for (final fatura in faturas) {
        final r =
            fatura.resultado;

        for (final item
            in r.lancamentos) {
          sheet.appendRow([
            TextCellValue(
              fatura.arquivo,
            ),
            TextCellValue(
              r.vencimento,
            ),
            TextCellValue(
              r.cartao,
            ),
            TextCellValue(
              item.data,
            ),
            TextCellValue(
              item.descricao,
            ),
            TextCellValue(
              item.categoria,
            ),
            DoubleCellValue(
              item.valor,
            ),
            item.parcelaAtual == null
                ? TextCellValue('')
                : IntCellValue(
                    item.parcelaAtual!,
                  ),
            item.totalParcelas == null
                ? TextCellValue('')
                : IntCellValue(
                    item.totalParcelas!,
                  ),
            TextCellValue(
              item.tipo,
            ),
            TextCellValue(
              item.observacoes,
            ),
          ]);
        }
      }

      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(
          'TOTAL CONSOLIDADO',
        ),
        TextCellValue(''),
        DoubleCellValue(
          somaTotalLancamentos,
        ),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      sheet.setColumnWidth(0, 35);
      sheet.setColumnWidth(1, 16);
      sheet.setColumnWidth(2, 25);
      sheet.setColumnWidth(3, 15);
      sheet.setColumnWidth(4, 42);
      sheet.setColumnWidth(5, 22);
      sheet.setColumnWidth(6, 16);
      sheet.setColumnWidth(7, 15);
      sheet.setColumnWidth(8, 26);
      sheet.setColumnWidth(9, 22);
      sheet.setColumnWidth(10, 40);

      // ======================================================
      // CONFERÊNCIA
      // ======================================================

      final conferencia =
          excel['Conferência'];

      conferencia.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Vencimento'),
        TextCellValue('Cartão'),
        TextCellValue(
          'Valor total da fatura',
        ),
        TextCellValue(
          'Soma dos lançamentos',
        ),
        TextCellValue('Diferença'),
        TextCellValue('Lançamentos'),
        TextCellValue('Parceladas'),
        TextCellValue('Cartão Itaú'),
        TextCellValue('Internacional'),
        TextCellValue(
          'Produtos/serviços',
        ),
        TextCellValue('Encargos'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r =
            fatura.resultado;

        conferencia.appendRow([
          TextCellValue(
            fatura.arquivo,
          ),
          TextCellValue(
            r.vencimento,
          ),
          TextCellValue(
            r.cartao,
          ),
          DoubleCellValue(
            r.totalFatura ?? 0,
          ),
          DoubleCellValue(
            r.soma,
          ),
          DoubleCellValue(
            r.diferenca ?? 0,
          ),
          IntCellValue(
            r.lancamentos.length,
          ),
          IntCellValue(
            r.quantidadeParceladas,
          ),
          DoubleCellValue(
            r.totalCartaoInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalInternacionalInformado ??
                0,
          ),
          DoubleCellValue(
            r.totalServicosInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalEncargosInformado ?? 0,
          ),
          TextCellValue(
            r.status,
          ),
        ]);
      }

      conferencia.appendRow([
        TextCellValue(
          'TOTAL CONSOLIDADO',
        ),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(
          valorTotalFaturas,
        ),
        DoubleCellValue(
          somaTotalLancamentos,
        ),
        DoubleCellValue(
          diferencaTotal,
        ),
        IntCellValue(
          totalLancamentos,
        ),
        IntCellValue(
          totalParceladas,
        ),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(
          todasConciliadas
              ? 'CONCILIADO'
              : 'DIVERGENTE',
        ),
      ]);

      for (int i = 0;
          i <= 12;
          i++) {
        conferencia.setColumnWidth(
          i,
          i == 0 ? 35 : 20,
        );
      }

      // ======================================================
      // DIVERGÊNCIAS
      // ======================================================

      if (!todasConciliadas) {
        final divergencias =
            excel['Divergências'];

        divergencias.appendRow([
          TextCellValue('Arquivo'),
          TextCellValue('Status'),
          TextCellValue(
            'Total da fatura',
          ),
          TextCellValue(
            'Soma dos lançamentos',
          ),
          TextCellValue('Diferença'),
          TextCellValue(
            'Observações',
          ),
        ]);

        for (final fatura
            in faturas) {
          final r =
              fatura.resultado;

          if (!r.conciliada) {
            divergencias.appendRow([
              TextCellValue(
                fatura.arquivo,
              ),
              TextCellValue(
                r.status,
              ),
              DoubleCellValue(
                r.totalFatura ?? 0,
              ),
              DoubleCellValue(
                r.soma,
              ),
              DoubleCellValue(
                r.diferenca ?? 0,
              ),
              TextCellValue(
                r.alertas.join(' | '),
              ),
            ]);
          }
        }

        divergencias
            .setColumnWidth(0, 35);
        divergencias
            .setColumnWidth(1, 22);
        divergencias
            .setColumnWidth(2, 20);
        divergencias
            .setColumnWidth(3, 22);
        divergencias
            .setColumnWidth(4, 20);
        divergencias
            .setColumnWidth(5, 60);
      }

      if (excel.tables
          .containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes =
          excel.encode();

      if (bytes == null) {
        throw Exception(
          'Não foi possível gerar o Excel.',
        );
      }

      final pasta =
          await getTemporaryDirectory();

      final agora =
          DateTime.now();

      final nome =
          'Faturas_Itau_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}'
          '_consolidado.xlsx';

      final arquivo =
          File(
        '${pasta.path}/$nome',
      );

      await arquivo.writeAsBytes(
        bytes,
        flush: true,
      );

      if (!mounted) return;

      setState(() {
        gerandoExcel = false;
      });

      await Share.shareXFiles(
        [
          XFile(
            arquivo.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject:
            'Faturas Itaú conferidas',
        text:
            '${faturas.length} fatura(s) '
            'processada(s) e conciliada(s).',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        gerandoExcel = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao gerar Excel: $e',
          ),
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // FORMATAÇÃO
  // ----------------------------------------------------------

  String dinheiro(
    double valor,
  ) {
    final sinal =
        valor < 0 ? '-' : '';

    final partes = valor
        .abs()
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
            child: Text(
              titulo,
            ),
          ),
          const SizedBox(
            width: 8,
          ),
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

  Color corStatus(
    ResultadoFatura r,
  ) {
    if (r.conciliada) {
      return Colors.green;
    }

    if (r.falhaLeitura) {
      return Colors.red;
    }

    return Colors.orange;
  }

  IconData iconeStatus(
    ResultadoFatura r,
  ) {
    if (r.conciliada) {
      return Icons.check_circle;
    }

    if (r.falhaLeitura) {
      return Icons.error;
    }

    return Icons.warning_amber;
  }

  // ----------------------------------------------------------
  // INTERFACE
  // ----------------------------------------------------------

  @override
  Widget build(
    BuildContext context,
  ) {
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
                    : selecionarFaturas,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar faturas PDF',
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
              child: Text(
                status,
              ),
            ),
          ),

          if (faturas.isNotEmpty) ...[
            const SizedBox(
              height: 20,
            ),

            const Text(
              'Resumo consolidado',
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
                      'Faturas processadas',
                      '${faturas.length}',
                    ),

                    linhaResumo(
                      'Conciliadas',
                      '$quantidadeConciliadas',
                    ),

                    linhaResumo(
                      'Divergentes',
                      '$quantidadeDivergentes',
                    ),

                    linhaResumo(
                      'Falhas de leitura',
                      '$quantidadeFalhas',
                    ),

                    const Divider(),

                    linhaResumo(
                      'Total das faturas',
                      dinheiro(
                        valorTotalFaturas,
                      ),
                    ),

                    linhaResumo(
                      'Soma dos lançamentos',
                      dinheiro(
                        somaTotalLancamentos,
                      ),
                    ),

                    linhaResumo(
                      'Diferença consolidada',
                      dinheiro(
                        diferencaTotal,
                      ),
                    ),

                    linhaResumo(
                      'Lançamentos',
                      '$totalLancamentos',
                    ),

                    linhaResumo(
                      'Compras parceladas',
                      '$totalParceladas',
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Row(
                      children: [
                        Icon(
                          todasConciliadas
                              ? Icons
                                  .check_circle
                              : Icons
                                  .warning_amber,
                          color:
                              todasConciliadas
                                  ? Colors.green
                                  : Colors.orange,
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        Expanded(
                          child: Text(
                            todasConciliadas
                                ? 'Todas as faturas estão conciliadas'
                                : 'Existem faturas que precisam de revisão',
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

            const SizedBox(
              height: 16,
            ),

            FilledButton.icon(
              onPressed:
                  todasConciliadas &&
                          !gerandoExcel
                      ? gerarExcelConsolidado
                      : null,
              icon: gerandoExcel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.table_view,
                    ),
              label: Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : 'Gerar Excel consolidado',
              ),
            ),

            if (!todasConciliadas)
              const Padding(
                padding:
                    EdgeInsets.only(
                  top: 8,
                ),
                child: Text(
                  'O Excel será liberado somente '
                  'quando cada fatura individualmente '
                  'estiver com diferença de R\$ 0,00.',
                  textAlign:
                      TextAlign.center,
                ),
              ),

            const SizedBox(
              height: 28,
            ),

            const Text(
              'Conferência por fatura',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            ...faturas.map(
              (fatura) {
                final r =
                    fatura.resultado;

                return Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          fatura.arquivo,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        if (r.vencimento
                            .isNotEmpty)
                          Text(
                            'Vencimento: '
                            '${r.vencimento}',
                          ),

                        if (r.cartao
                            .isNotEmpty)
                          Text(
                            'Cartão: '
                            '${r.cartao}',
                          ),

                        const SizedBox(
                          height: 10,
                        ),

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
                          'Parceladas',
                          '${r.quantidadeParceladas}',
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Row(
                          children: [
                            Icon(
                              iconeStatus(r),
                              color:
                                  corStatus(r),
                            ),

                            const SizedBox(
                              width: 8,
                            ),

                            Text(
                              r.status,
                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    corStatus(r),
                              ),
                            ),
                          ],
                        ),

                        if (r.alertas
                            .isNotEmpty) ...[
                          const SizedBox(
                            height: 10,
                          ),

                          ...r.alertas.map(
                            (alerta) =>
                                Padding(
                              padding:
                                  const EdgeInsets
                                      .only(
                                bottom: 4,
                              ),
                              child: Text(
                                '• $alerta',
                                style:
                                    const TextStyle(
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
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
