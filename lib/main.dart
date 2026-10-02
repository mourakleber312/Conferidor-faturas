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
  final double? totalLancamentosAtuaisInformado;
  final double? totalEncargosInformado;
  final double? saldoFinanciadoInformado;

  final String vencimento;
  final String cartao;

  final List<Lancamento> lancamentos;
  final List<Lancamento> compras;
  final List<String> alertas;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    required this.compras,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
    this.totalLancamentosAtuaisInformado,
    this.totalEncargosInformado,
    this.saldoFinanciadoInformado,
    this.vencimento = '',
    this.cartao = '',
    this.alertas = const [],
  });

  double get soma =>
      lancamentos.fold<double>(0, (s, e) => s + e.valor);

  double get somaCompras =>
      compras.fold<double>(0, (s, e) => s + e.valor);

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  double? get diferencaCartao {
    if (totalCartaoInformado == null) return null;
    return totalCartaoInformado! - somaCompras;
  }

  int get quantidadeParceladas =>
      compras.where((e) => e.parcelada).length;

  bool get comprasConciliadas {
    if (totalCartaoInformado == null) {
      return compras.isNotEmpty;
    }

    return (totalCartaoInformado! - somaCompras).abs() < 0.02;
  }

  bool get totalConciliado {
    if (totalFatura == null) return false;
    return (totalFatura! - soma).abs() < 0.02;
  }

  bool get conciliada =>
      totalConciliado && comprasConciliadas;

  bool get falhaLeitura =>
      totalFatura == null &&
      totalCartaoInformado == null &&
      compras.isEmpty;

  String get status {
    if (falhaLeitura) return 'FALHA DE LEITURA';
    if (conciliada) return 'CONCILIADA';

    if (totalConciliado && !comprasConciliadas) {
      return 'INCOMPLETA';
    }

    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;
  final String textoLayout;
  final String textoBruto;
  final String parserEscolhido;

  FaturaProcessada({
    required this.arquivo,
    required this.resultado,
    required this.textoLayout,
    required this.textoBruto,
    required this.parserEscolhido,
  });
}

class CandidatoParser {
  final String nome;
  final List<Lancamento> compras;

  CandidatoParser(
    this.nome,
    this.compras,
  );

  double get soma =>
      compras.fold<double>(0, (s, e) => s + e.valor);
}

// ============================================================
// PARSER ITAÚ V7.1
// ============================================================

class ParserItau {
  // ==========================================================
  // NORMALIZAÇÃO
  // ==========================================================

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
    var t = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    final negativo = t.startsWith('-');

    if (negativo) {
      t = t.substring(1);
    }

    t = t.replaceAll('.', '').replaceAll(',', '.');

    final n = double.tryParse(t) ?? 0.0;

    return negativo ? -n : n;
  }

  static bool dataValida(String data) {
    final partes = data.split('/');

    if (partes.length != 2) return false;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);

    if (dia == null || mes == null) return false;

    return dia >= 1 &&
        dia <= 31 &&
        mes >= 1 &&
        mes <= 12;
  }

  // ==========================================================
  // NORMALIZAÇÃO NUMÉRICA SEGURA
  // ==========================================================

  static String removerEspacosNumericos(String texto) {
    var atual = texto;
    var anterior = '';

    while (anterior != atual) {
      anterior = atual;

      atual = atual.replaceAllMapped(
        RegExp(r'(\d)\s+(\d)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );

      atual = atual.replaceAllMapped(
        RegExp(r'(\d)\s+([,.])'),
        (m) => '${m.group(1)}${m.group(2)}',
      );

      atual = atual.replaceAllMapped(
        RegExp(r'([,.])\s+(\d)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );

      atual = atual.replaceAllMapped(
        RegExp(r'(\d)\s*/\s*(\d)'),
        (m) => '${m.group(1)}/${m.group(2)}',
      );
    }

    return atual;
  }

  static String normalizarLinha(String linha) {
    return limparEspacos(
      removerEspacosNumericos(linha),
    );
  }

  static String compactarLinhaParaBusca(String linha) {
    return semAcentos(linha)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
  }

  static bool contemCompactado(
    String linha,
    String procurado,
  ) {
    return compactarLinhaParaBusca(linha).contains(
      compactarLinhaParaBusca(procurado),
    );
  }

  // ==========================================================
  // VALORES
  // ==========================================================

  static List<RegExpMatch> encontrarValores(String linha) {
    final normalizada = removerEspacosNumericos(linha);

    return RegExp(
      r'-?\d[\d.]*,\d{2}',
    ).allMatches(normalizada).toList();
  }

  // ==========================================================
  // TOTAIS OFICIAIS
  // ==========================================================

  static double? procurarSubtotal(
    String texto,
    List<String> marcadores,
  ) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    for (var i = 0; i < linhas.length; i++) {
      final linha = removerEspacosNumericos(
        linhas[i],
      );

      for (final marcador in marcadores) {
        if (!contemCompactado(linha, marcador)) {
          continue;
        }

        final valores = encontrarValores(linha);

        if (valores.isNotEmpty) {
          return moedaParaDouble(
            valores.last.group(0)!,
          );
        }

        // Fallback: valor na próxima linha.
        if (i + 1 < linhas.length) {
          final prox = removerEspacosNumericos(
            linhas[i + 1],
          );

          final valoresProx = encontrarValores(prox);

          if (valoresProx.isNotEmpty) {
            return moedaParaDouble(
              valoresProx.first.group(0)!,
            );
          }
        }
      }
    }

    // Segundo fallback usando texto compactado.
    final normalizado = removerEspacosNumericos(texto);
    final c = compactar(normalizado);

    for (final marcador in marcadores) {
      final alvo = compactar(marcador);
      final pos = c.indexOf(alvo);

      if (pos < 0) continue;

      final depois = c.substring(
        pos + alvo.length,
      );

      final m = RegExp(
        r'-?[\d.]+,\d{2}',
      ).firstMatch(depois);

      if (m != null) {
        return moedaParaDouble(
          m.group(0)!,
        );
      }
    }

    return null;
  }

  static double? procurarTotalFatura(String texto) {
    return procurarSubtotal(
      texto,
      const [
        'Total desta fatura',
        'Total da fatura',
      ],
    );
  }

  static String procurarVencimento(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    for (final original in linhas) {
      final linha = removerEspacosNumericos(original);

      if (!contemCompactado(
        linha,
        'vencimento',
      )) {
        continue;
      }

      final m = RegExp(
        r'(\d{2}/\d{2}/\d{4})',
      ).firstMatch(linha);

      if (m != null) {
        return m.group(1)!;
      }
    }

    return '';
  }

  static String procurarCartao(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    for (final original in linhas) {
      final linha = normalizarLinha(original);

      if (!contemCompactado(
        linha,
        'cartao',
      )) {
        continue;
      }

      final m = RegExp(
        r'(\d{4}\.[Xx]{4}\.[Xx]{4}\.\d{4})',
      ).firstMatch(linha);

      if (m != null) {
        return m.group(1)!;
      }
    }

    return '';
  }

  // ==========================================================
  // CATEGORIAS
  // ==========================================================

  static const categorias = <String>[
    'restaurante',
    'supermercado',
    'vestuario',
    'vestuário',
    'saude',
    'saúde',
    'servicos',
    'serviços',
    'outros',
    'lazer',
    'eletronicos',
    'eletrônicos',
    'hotel',
    'transporte',
    'viagem',
    'educacao',
    'educação',
    'health',
    'money',
    'supermarket',
    'automobile',
    'automóvel',
  ];

  static String normalizarCategoria(String valor) {
    final c = semAcentos(valor).toLowerCase().trim();

    const mapa = <String, String>{
      'vestuario': 'vestuário',
      'saude': 'saúde',
      'servicos': 'serviços',
      'educacao': 'educação',
      'eletronicos': 'eletrônicos',
      'supermarket': 'supermercado',
      'health': 'saúde',
      'money': 'serviços',
      'automobile': 'automóvel',
    };

    return mapa[c] ?? c;
  }

  static String detectarCategoria(String linha) {
    final c = compactarLinhaParaBusca(linha);

    for (final categoria in categorias) {
      final cat = compactarLinhaParaBusca(categoria);

      if (c.startsWith(cat)) {
        return normalizarCategoria(categoria);
      }
    }

    return 'outros';
  }

  static bool pareceCategoria(String linha) {
    final c = compactarLinhaParaBusca(linha);

    for (final categoria in categorias) {
      if (c.startsWith(
        compactarLinhaParaBusca(categoria),
      )) {
        return true;
      }
    }

    return false;
  }

  // ==========================================================
  // SEÇÕES
  // ==========================================================

  static bool inicioCompras(String linha) {
    final c = compactarLinhaParaBusca(linha);

    return c.contains('lancamentos:comprasesaques') ||
        c.contains('lancamentoscomprasesaques');
  }

  static bool fimCompras(String linha) {
    final c = compactarLinhaParaBusca(linha);

    return c.contains('lancamentosnocartao') ||
        c.contains('lancamentosinternacionais') ||
        c.contains('lancamentos:produtoseservicos') ||
        c.contains('lancamentosprodutoseservicos') ||
        c.contains('comprasparceladas-proximasfaturas') ||
        c.contains('comprasparceladasproximasfaturas');
  }

  static bool linhaIgnorada(String linha) {
    final c = compactarLinhaParaBusca(linha);

    return c.isEmpty ||
        c.contains('dataestabelecimentovaloremr') ||
        c.contains('dataestabelecimento') ||
        c.contains('continua...') ||
        c == 'continua' ||
        c.contains('pagamentosefetuados') ||
        c.contains('totaldospagamentos') ||
        c.contains('resumodafatura') ||
        c.contains('pagamentominimo') ||
        c.contains('limitedecredito');
  }

  // ==========================================================
  // PARCELAS
  // ==========================================================

  static bool ehParcelaValida(
    int atual,
    int total,
  ) {
    return atual >= 1 &&
        total >= atual &&
        total <= 60;
  }

  // ==========================================================
  // PARSE DE UMA TRANSAÇÃO
  // ==========================================================

  static Lancamento? parseTransacao(
    String texto, {
    String categoria = 'outros',
    String origem = 'Parser v7.1',
  }) {
    final linha = normalizarLinha(texto);

    if (linhaIgnorada(linha)) return null;

    final inicio = RegExp(
      r'^\s*(\d{2}/\d{2})\s+',
    ).firstMatch(linha);

    if (inicio == null) return null;

    final data = inicio.group(1)!;

    if (!dataValida(data)) return null;

    var restante = linha.substring(inicio.end).trim();

    final valorMatch = RegExp(
      r'(-?\d[\d.]*,\d{2})\s*$',
    ).firstMatch(restante);

    if (valorMatch == null) return null;

    final valor = moedaParaDouble(
      valorMatch.group(1)!,
    );

    if (valor.abs() > 100000) {
      return null;
    }

    var descricao = restante
        .substring(0, valorMatch.start)
        .trim();

    if (descricao.isEmpty) return null;

    int? parcelaAtual;
    int? totalParcelas;

    final parcelaMatch = RegExp(
      r'(\d{1,2})\s*/\s*(\d{1,2})\s*$',
    ).firstMatch(descricao);

    if (parcelaMatch != null) {
      final atual = int.tryParse(
        parcelaMatch.group(1)!,
      );

      final total = int.tryParse(
        parcelaMatch.group(2)!,
      );

      if (atual != null &&
          total != null &&
          ehParcelaValida(atual, total)) {
        parcelaAtual = atual;
        totalParcelas = total;

        descricao = descricao
            .substring(0, parcelaMatch.start)
            .trim();
      }
    }

    if (descricao.isEmpty) return null;

    return Lancamento(
      data: data,
      descricao: descricao,
      categoria: categoria,
      valor: valor,
      parcelaAtual: parcelaAtual,
      totalParcelas: totalParcelas,
      tipo:
          parcelaAtual == null ? 'À vista' : 'Parcelada',
      observacoes: origem,
    );
  }

  // ==========================================================
  // EXTRAÇÃO LINEAR
  // ==========================================================

  static List<Lancamento> extrairLinear(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    final resultado = <Lancamento>[];

    bool dentro = false;

    for (var i = 0; i < linhas.length; i++) {
      final linha = normalizarLinha(linhas[i]);

      if (inicioCompras(linha)) {
        dentro = true;
        continue;
      }

      if (!dentro) continue;

      if (fimCompras(linha)) {
        dentro = false;
        continue;
      }

      if (linhaIgnorada(linha)) continue;

      var categoria = 'outros';

      if (i + 1 < linhas.length &&
          pareceCategoria(linhas[i + 1])) {
        categoria = detectarCategoria(
          linhas[i + 1],
        );
      }

      final item = parseTransacao(
        linha,
        categoria: categoria,
        origem: 'Linear v7.1',
      );

      if (item != null) {
        resultado.add(item);
      }
    }

    return resultado;
  }

  // ==========================================================
  // EXTRAÇÃO GLOBAL
  //
  // CORREÇÃO CRÍTICA V7.1:
  // NÃO usa (?m) dentro do padrão.
  // multiLine é passado como parâmetro do RegExp.
  // ==========================================================

  static List<Lancamento> extrairGlobal(String texto) {
    final resultado = <Lancamento>[];

    final normalizado = removerEspacosNumericos(
      texto.replaceAll('\r', '\n'),
    );

    final rx = RegExp(
      r'^\s*(\d{2}/\d{2})'
      r'\s+'
      r'(.+?)'
      r'(?:\s+(\d{1,2})/(\d{1,2}))?'
      r'\s+'
      r'(-?\d[\d.]*,\d{2})'
      r'\s*$',
      multiLine: true,
    );

    for (final m in rx.allMatches(normalizado)) {
      final data = m.group(1);

      if (data == null || !dataValida(data)) {
        continue;
      }

      var descricao = limparEspacos(
        m.group(2) ?? '',
      );

      if (descricao.isEmpty) continue;

      final valorTexto = m.group(5);

      if (valorTexto == null) continue;

      final valor = moedaParaDouble(valorTexto);

      if (valor.abs() > 100000) continue;

      int? parcelaAtual;
      int? totalParcelas;

      final parcelaA = m.group(3);
      final parcelaT = m.group(4);

      if (parcelaA != null &&
          parcelaT != null) {
        final a = int.tryParse(parcelaA);
        final t = int.tryParse(parcelaT);

        if (a != null &&
            t != null &&
            ehParcelaValida(a, t)) {
          parcelaAtual = a;
          totalParcelas = t;
        } else {
          descricao =
              '$descricao $parcelaA/$parcelaT';
        }
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: 'outros',
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: parcelaAtual == null
              ? 'À vista'
              : 'Parcelada',
          observacoes: 'Regex global v7.1',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // EXTRAÇÃO FRAGMENTADA
  // ==========================================================

  static List<Lancamento> extrairFragmentado(
    String texto,
  ) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    final resultado = <Lancamento>[];

    bool dentro = false;

    for (var i = 0; i < linhas.length; i++) {
      final linha = normalizarLinha(linhas[i]);

      if (inicioCompras(linha)) {
        dentro = true;
        continue;
      }

      if (!dentro) continue;

      if (fimCompras(linha)) {
        dentro = false;
        continue;
      }

      if (linhaIgnorada(linha)) continue;

      var categoria = 'outros';

      if (i + 1 < linhas.length &&
          pareceCategoria(linhas[i + 1])) {
        categoria = detectarCategoria(
          linhas[i + 1],
        );
      }

      var item = parseTransacao(
        linha,
        categoria: categoria,
        origem: 'Fragmentado direto v7.1',
      );

      if (item != null) {
        resultado.add(item);
        continue;
      }

      var combinado = linha;

      for (var j = 1; j <= 2; j++) {
        if (i + j >= linhas.length) break;

        final proxima = normalizarLinha(
          linhas[i + j],
        );

        if (inicioCompras(proxima) ||
            fimCompras(proxima) ||
            pareceCategoria(proxima)) {
          break;
        }

        combinado = '$combinado $proxima';

        item = parseTransacao(
          combinado,
          categoria: categoria,
          origem:
              'Fragmentado combinado v7.1',
        );

        if (item != null) {
          resultado.add(item);
          i += j;
          break;
        }
      }
    }

    return resultado;
  }

  // ==========================================================
  // REMOÇÃO DE DUPLICADOS
  // ==========================================================

  static List<Lancamento> removerDuplicados(
    List<Lancamento> lista,
  ) {
    final resultado = <Lancamento>[];
    final chaves = <String>{};

    for (final item in lista) {
      final chave =
          '${item.data}|'
          '${compactar(item.descricao)}|'
          '${item.valor.toStringAsFixed(2)}|'
          '${item.parcelaAtual ?? ''}|'
          '${item.totalParcelas ?? ''}';

      if (chaves.add(chave)) {
        resultado.add(item);
      }
    }

    return resultado;
  }

  // ==========================================================
  // SELEÇÃO DO MELHOR CANDIDATO
  // ==========================================================

  static CandidatoParser escolherCompras(
    String texto,
    double? totalCartao,
  ) {
    final candidatos = <CandidatoParser>[
      CandidatoParser(
        'LINEAR',
        removerDuplicados(
          extrairLinear(texto),
        ),
      ),
      CandidatoParser(
        'GLOBAL',
        removerDuplicados(
          extrairGlobal(texto),
        ),
      ),
      CandidatoParser(
        'FRAGMENTADO',
        removerDuplicados(
          extrairFragmentado(texto),
        ),
      ),
    ];

    if (totalCartao == null) {
      candidatos.sort(
        (a, b) => b.compras.length.compareTo(
          a.compras.length,
        ),
      );

      return candidatos.first;
    }

    candidatos.sort((a, b) {
      final erroA =
          (totalCartao - a.soma).abs();

      final erroB =
          (totalCartao - b.soma).abs();

      final comparacao =
          erroA.compareTo(erroB);

      if (comparacao != 0) {
        return comparacao;
      }

      if (a.compras.length !=
          b.compras.length) {
        return b.compras.length.compareTo(
          a.compras.length,
        );
      }

      final parcelasA = a.compras
          .where((e) => e.parcelada)
          .length;

      final parcelasB = b.compras
          .where((e) => e.parcelada)
          .length;

      return parcelasB.compareTo(parcelasA);
    });

    return candidatos.first;
  }

  // ==========================================================
  // INTERNACIONAL
  // ==========================================================

  static List<Lancamento> lerInternacional(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final transacoes = procurarSubtotal(
      texto,
      const [
        'Total transações inter. em R\$',
        'Total transacoes inter. em R\$',
      ],
    );

    final iof = procurarSubtotal(
      texto,
      const [
        'Repasse de IOF em R\$',
        'Repasse de IOF',
      ],
    );

    if (transacoes != null &&
        transacoes.abs() >= 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'Transações internacionais',
          categoria: 'internacional',
          valor: transacoes,
          tipo: 'Internacional',
          observacoes:
              'Subtotal oficial internacional',
        ),
      );
    }

    if (iof != null &&
        iof.abs() >= 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'IOF - transações internacionais',
          categoria: 'encargos',
          valor: iof,
          tipo: 'IOF internacional',
          observacoes:
              'IOF internacional informado',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PRODUTOS / SERVIÇOS
  // ==========================================================

  static List<Lancamento> lerProdutosServicos(
    double? subtotal,
  ) {
    if (subtotal == null ||
        subtotal.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao: 'Produtos e serviços',
        categoria: 'produtos e serviços',
        valor: subtotal,
        tipo: 'Produto/Serviço',
        observacoes:
            'Subtotal oficial de produtos e serviços',
      ),
    ];
  }

  // ==========================================================
  // ENCARGOS
  // ==========================================================

  static List<Lancamento> lerEncargos(
    double? subtotal,
  ) {
    if (subtotal == null ||
        subtotal.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao:
            'Encargos cobrados nesta fatura',
        categoria: 'encargos',
        valor: subtotal,
        tipo: 'Encargo financeiro',
        observacoes:
            'Subtotal oficial de encargos',
      ),
    ];
  }

  // ==========================================================
  // SALDO FINANCIADO
  // ==========================================================

  static List<Lancamento> lerSaldo(
    double? saldo,
  ) {
    if (saldo == null ||
        saldo.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao: 'Saldo financiado',
        categoria: 'financeiro',
        valor: saldo,
        tipo: 'Saldo financiado',
        observacoes:
            'Saldo financiado do resumo',
      ),
    ];
  }

  // ==========================================================
  // PROCESSAMENTO
  // ==========================================================

  static ResultadoFatura processar(
    String texto,
  ) {
    final alertas = <String>[];

    final totalFatura =
        procurarTotalFatura(texto);

    final totalCartao = procurarSubtotal(
      texto,
      const [
        'Lançamentos no cartão',
        'Lancamentos no cartao',
      ],
    );

    final totalInternacional =
        procurarSubtotal(
      texto,
      const [
        'Total lançamentos inter. em R\$',
        'Total lancamentos inter. em R\$',
      ],
    );

    final totalServicos =
        procurarSubtotal(
      texto,
      const [
        'Lançamentos produtos e serviços',
        'Lancamentos produtos e servicos',
        'Total produtos e serviços',
        'Total produtos e servicos',
      ],
    );

    final totalLancamentosAtuais =
        procurarSubtotal(
      texto,
      const [
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
      ],
    );

    final totalEncargos =
        procurarSubtotal(
      texto,
      const [
        'Total de encargos em R\$',
        'Total de encargos',
      ],
    );

    final saldoFinanciado =
        procurarSubtotal(
      texto,
      const [
        'Saldo financiado',
      ],
    );

    final candidato = escolherCompras(
      texto,
      totalCartao,
    );

    final compras = candidato.compras;

    final internacional =
        lerInternacional(texto);

    final produtos =
        lerProdutosServicos(
      totalServicos,
    );

    final encargos =
        lerEncargos(
      totalEncargos,
    );

    final saldo =
        lerSaldo(
      saldoFinanciado,
    );

    final somaCompras =
        compras.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalCartao != null) {
      final dif =
          totalCartao - somaCompras;

      if (dif.abs() >= 0.02) {
        alertas.add(
          'Compras não fecham o subtotal do cartão. '
          'Estratégia: ${candidato.nome}. '
          'Diferença: R\$ ${dif.toStringAsFixed(2)}',
        );
      }
    } else {
      alertas.add(
        'Subtotal do cartão não identificado.',
      );
    }

    if (compras.isEmpty) {
      alertas.add(
        'Nenhuma compra individual reconstruída.',
      );
    }

    final componentesAtuais =
        <Lancamento>[
      ...compras,
      ...internacional,
      ...produtos,
    ];

    final somaAtuais =
        componentesAtuais.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalLancamentosAtuais != null) {
      final dif =
          totalLancamentosAtuais -
          somaAtuais;

      if (dif.abs() >= 0.02) {
        alertas.add(
          'Lançamentos atuais não conciliados. '
          'Diferença: R\$ ${dif.toStringAsFixed(2)}',
        );
      }
    }

    final lancamentos =
        <Lancamento>[
      ...componentesAtuais,
      ...encargos,
      ...saldo,
    ];

    final somaFinal =
        lancamentos.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalFatura == null) {
      alertas.add(
        'Total da fatura não identificado.',
      );
    } else {
      final dif =
          totalFatura - somaFinal;

      if (dif.abs() >= 0.02) {
        alertas.add(
          'Total da fatura não conciliado. '
          'Diferença: R\$ ${dif.toStringAsFixed(2)}',
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
      totalLancamentosAtuaisInformado:
          totalLancamentosAtuais,
      totalEncargosInformado:
          totalEncargos,
      saldoFinanciadoInformado:
          saldoFinanciado,
      vencimento:
          procurarVencimento(texto),
      cartao:
          procurarCartao(texto),
      lancamentos: lancamentos,
      compras: compras,
      alertas: [
        'Estratégia de compras: ${candidato.nome}',
        ...alertas,
      ],
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
  bool gerandoDiagnostico = false;

  String status =
      'Selecione uma ou mais faturas Itaú em PDF.';

  final List<FaturaProcessada> faturas = [];

  int get quantidadeConciliadas =>
      faturas
          .where(
            (f) => f.resultado.conciliada,
          )
          .length;

  int get quantidadeDivergentes =>
      faturas
          .where(
            (f) =>
                f.resultado.status ==
                'DIVERGENTE',
          )
          .length;

  int get quantidadeIncompletas =>
      faturas
          .where(
            (f) =>
                f.resultado.status ==
                'INCOMPLETA',
          )
          .length;

  int get quantidadeFalhas =>
      faturas
          .where(
            (f) =>
                f.resultado.falhaLeitura,
          )
          .length;

  int get totalLancamentos =>
      faturas.fold<int>(
        0,
        (s, f) =>
            s +
            f.resultado.lancamentos.length,
      );

  int get totalCompras =>
      faturas.fold<int>(
        0,
        (s, f) =>
            s + f.resultado.compras.length,
      );

  int get totalParceladas =>
      faturas.fold<int>(
        0,
        (s, f) =>
            s +
            f.resultado
                .quantidadeParceladas,
      );

  double get valorTotalFaturas =>
      faturas.fold<double>(
        0,
        (s, f) =>
            s +
            (f.resultado.totalFatura ??
                0),
      );

  double get somaTotalLancamentos =>
      faturas.fold<double>(
        0,
        (s, f) =>
            s + f.resultado.soma,
      );

  bool get todasConciliadas =>
      faturas.isNotEmpty &&
      faturas.every(
        (f) => f.resultado.conciliada,
      );

  // ==========================================================
  // MELHOR RESULTADO
  // ==========================================================

  ResultadoFatura escolherMelhor(
    ResultadoFatura a,
    ResultadoFatura b,
  ) {
    if (a.conciliada != b.conciliada) {
      return a.conciliada ? a : b;
    }

    final erroCartaoA =
        a.diferencaCartao?.abs() ??
        double.infinity;

    final erroCartaoB =
        b.diferencaCartao?.abs() ??
        double.infinity;

    if ((erroCartaoA - erroCartaoB)
            .abs() >
        0.005) {
      return erroCartaoA < erroCartaoB
          ? a
          : b;
    }

    if (a.quantidadeParceladas !=
        b.quantidadeParceladas) {
      return a.quantidadeParceladas >
              b.quantidadeParceladas
          ? a
          : b;
    }

    if (a.compras.length !=
        b.compras.length) {
      return a.compras.length >
              b.compras.length
          ? a
          : b;
    }

    final erroA =
        a.diferenca?.abs() ??
        double.infinity;

    final erroB =
        b.diferenca?.abs() ??
        double.infinity;

    return erroA <= erroB ? a : b;
  }

  // ==========================================================
  // PROCESSAR PDFs
  // ==========================================================

  Future<void> selecionarFaturas() async {
    final escolha =
        await FilePicker.platform.pickFiles(
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
          'Iniciando processamento...';
    });

    for (var i = 0;
        i < escolha.files.length;
        i++) {
      final arquivo = escolha.files[i];

      setState(() {
        status =
            'Analisando ${i + 1} de '
            '${escolha.files.length}\n'
            '${arquivo.name}';
      });

      try {
        if (arquivo.path == null) {
          throw Exception(
            'Arquivo sem caminho local.',
          );
        }

        final bytes = await File(
          arquivo.path!,
        ).readAsBytes();

        final documento = PdfDocument(
          inputBytes: bytes,
        );

        final extrator =
            PdfTextExtractor(documento);

        final textoBruto =
            extrator.extractText();

        final textoLayout =
            extrator.extractText(
          layoutText: true,
        );

        documento.dispose();

        final resultadoLayout =
            ParserItau.processar(
          textoLayout,
        );

        final resultadoBruto =
            ParserItau.processar(
          textoBruto,
        );

        final resultado =
            escolherMelhor(
          resultadoLayout,
          resultadoBruto,
        );

        final fonte = identical(
          resultado,
          resultadoLayout,
        )
            ? 'LAYOUT'
            : 'BRUTO';

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: resultado,
            textoLayout: textoLayout,
            textoBruto: textoBruto,
            parserEscolhido: fonte,
          ),
        );
      } catch (e, stack) {
        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            textoLayout: '',
            textoBruto: '',
            parserEscolhido: 'ERRO',
            resultado: ResultadoFatura(
              totalFatura: null,
              lancamentos: const [],
              compras: const [],
              alertas: [
                'Falha ao processar: $e',
                'Stack: $stack',
              ],
            ),
          ),
        );
      }
    }

    if (!mounted) return;

    setState(() {
      processando = false;

      status =
          '${faturas.length} fatura(s) processada(s).\n'
          '$quantidadeConciliadas conciliada(s), '
          '$quantidadeIncompletas incompleta(s), '
          '$quantidadeDivergentes divergente(s), '
          '$quantidadeFalhas falha(s).';
    });
  }

  // ==========================================================
  // DIAGNÓSTICO INDIVIDUAL
  // ==========================================================

  String montarDiagnosticoFatura(
    FaturaProcessada fatura, {
    bool incluirTextos = true,
  }) {
    final r = fatura.resultado;

    final b = StringBuffer();

    b.writeln(
      '============================================================',
    );
    b.writeln(
      'DIAGNÓSTICO - CONFERIDOR DE FATURAS ITAÚ',
    );
    b.writeln('Parser: v7.1');
    b.writeln(
      'Arquivo: ${fatura.arquivo}',
    );
    b.writeln(
      'Fonte escolhida: '
      '${fatura.parserEscolhido}',
    );
    b.writeln(
      'Status: ${r.status}',
    );
    b.writeln(
      'Vencimento: ${r.vencimento}',
    );
    b.writeln(
      'Cartão: ${r.cartao}',
    );
    b.writeln();

    b.writeln(
      '===== CONFERÊNCIA =====',
    );

    b.writeln(
      'Total da fatura: '
      '${r.totalFatura}',
    );
    b.writeln(
      'Subtotal cartão: '
      '${r.totalCartaoInformado}',
    );
    b.writeln(
      'Soma compras: '
      '${r.somaCompras}',
    );
    b.writeln(
      'Diferença cartão: '
      '${r.diferencaCartao}',
    );
    b.writeln(
      'Total internacional: '
      '${r.totalInternacionalInformado}',
    );
    b.writeln(
      'Produtos/serviços: '
      '${r.totalServicosInformado}',
    );
    b.writeln(
      'Total lançamentos atuais: '
      '${r.totalLancamentosAtuaisInformado}',
    );
    b.writeln(
      'Encargos: '
      '${r.totalEncargosInformado}',
    );
    b.writeln(
      'Saldo financiado: '
      '${r.saldoFinanciadoInformado}',
    );
    b.writeln(
      'Soma geral: ${r.soma}',
    );
    b.writeln(
      'Diferença geral: '
      '${r.diferenca}',
    );
    b.writeln(
      'Compras: ${r.compras.length}',
    );
    b.writeln(
      'Parceladas: '
      '${r.quantidadeParceladas}',
    );

    b.writeln();
    b.writeln(
      '===== ALERTAS =====',
    );

    if (r.alertas.isEmpty) {
      b.writeln('Nenhum alerta.');
    } else {
      for (final alerta in r.alertas) {
        b.writeln('- $alerta');
      }
    }

    b.writeln();
    b.writeln(
      '===== COMPRAS RECONSTRUÍDAS =====',
    );

    if (r.compras.isEmpty) {
      b.writeln(
        'Nenhuma compra reconstruída.',
      );
    } else {
      for (final item in r.compras) {
        final parcela = item.parcelada
            ? '${item.parcelaAtual}/'
                '${item.totalParcelas}'
            : '';

        b.writeln(
          '${item.data} | '
          '${item.descricao} | '
          '${item.valor.toStringAsFixed(2)} | '
          '$parcela | '
          '${item.categoria} | '
          '${item.observacoes}',
        );
      }
    }

    b.writeln();
    b.writeln(
      '===== TODOS OS LANÇAMENTOS =====',
    );

    if (r.lancamentos.isEmpty) {
      b.writeln(
        'Nenhum lançamento.',
      );
    } else {
      for (final item
          in r.lancamentos) {
        b.writeln(
          '${item.data} | '
          '${item.descricao} | '
          '${item.valor.toStringAsFixed(2)} | '
          '${item.tipo} | '
          '${item.categoria} | '
          '${item.observacoes}',
        );
      }
    }

    if (incluirTextos) {
      b.writeln();
      b.writeln(
        '===== TEXTO COM LAYOUT =====',
      );
      b.writeln(
        fatura.textoLayout,
      );

      b.writeln();
      b.writeln(
        '===== TEXTO BRUTO =====',
      );
      b.writeln(
        fatura.textoBruto,
      );
    }

    return b.toString();
  }

  Future<void> gerarDiagnostico(
    FaturaProcessada fatura,
  ) async {
    final pasta =
        await getTemporaryDirectory();

    final nome =
        fatura.arquivo.replaceAll(
      RegExp(
        r'[^A-Za-z0-9._-]',
      ),
      '_',
    );

    final arq = File(
      '${pasta.path}/'
      'diagnostico_$nome.txt',
    );

    await arq.writeAsString(
      montarDiagnosticoFatura(
        fatura,
      ),
    );

    await Share.shareXFiles(
      [
        XFile(
          arq.path,
          mimeType: 'text/plain',
        ),
      ],
    );
  }

  // ==========================================================
  // DIAGNÓSTICO TOTAL
  // ==========================================================

  Future<void>
      gerarDiagnosticoTotal() async {
    if (faturas.isEmpty) return;

    setState(() {
      gerandoDiagnostico = true;
    });

    try {
      final b = StringBuffer();

      b.writeln(
        '============================================================',
      );
      b.writeln(
        'DIAGNÓSTICO TOTAL - CONFERIDOR DE FATURAS ITAÚ',
      );
      b.writeln(
        'Parser: v7.1',
      );
      b.writeln(
        '============================================================',
      );
      b.writeln();

      b.writeln(
        '===== RESUMO GERAL =====',
      );
      b.writeln(
        'Faturas processadas: '
        '${faturas.length}',
      );
      b.writeln(
        'Conciliadas: '
        '$quantidadeConciliadas',
      );
      b.writeln(
        'Incompletas: '
        '$quantidadeIncompletas',
      );
      b.writeln(
        'Divergentes: '
        '$quantidadeDivergentes',
      );
      b.writeln(
        'Falhas de leitura: '
        '$quantidadeFalhas',
      );
      b.writeln(
        'Compras reconstruídas: '
        '$totalCompras',
      );
      b.writeln(
        'Compras parceladas: '
        '$totalParceladas',
      );
      b.writeln(
        'Valor total das faturas: '
        '$valorTotalFaturas',
      );
      b.writeln();

      b.writeln(
        '===== ÍNDICE DAS FATURAS =====',
      );

      for (var i = 0;
          i < faturas.length;
          i++) {
        final f = faturas[i];
        final r = f.resultado;

        b.writeln(
          '${i + 1}. '
          '${f.arquivo} | '
          '${r.status} | '
          'Total: ${r.totalFatura} | '
          'Cartão: '
          '${r.totalCartaoInformado} | '
          'Compras: ${r.somaCompras} | '
          'Dif.: '
          '${r.diferencaCartao} | '
          'Parceladas: '
          '${r.quantidadeParceladas} | '
          'Fonte: '
          '${f.parserEscolhido}',
        );
      }

      final ordenadas =
          <FaturaProcessada>[
        ...faturas.where(
          (f) =>
              !f.resultado.conciliada,
        ),
        ...faturas.where(
          (f) =>
              f.resultado.conciliada,
        ),
      ];

      for (var i = 0;
          i < ordenadas.length;
          i++) {
        b.writeln();
        b.writeln(
          '############################################################',
        );
        b.writeln(
          '# FATURA ${i + 1} '
          'DE ${ordenadas.length}',
        );
        b.writeln(
          '############################################################',
        );

        b.writeln(
          montarDiagnosticoFatura(
            ordenadas[i],
            incluirTextos: true,
          ),
        );
      }

      final pasta =
          await getTemporaryDirectory();

      final agora =
          DateTime.now();

      final nome =
          'diagnostico_total_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_'
          '${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}'
          '${agora.second.toString().padLeft(2, '0')}'
          '.txt';

      final arq = File(
        '${pasta.path}/$nome',
      );

      await arq.writeAsString(
        b.toString(),
      );

      await Share.shareXFiles(
        [
          XFile(
            arq.path,
            mimeType: 'text/plain',
          ),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar diagnóstico: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          gerandoDiagnostico = false;
        });
      }
    }
  }

  // ==========================================================
  // EXCEL
  // ==========================================================

  Future<void> gerarExcel() async {
    if (!todasConciliadas) return;

    setState(() {
      gerandoExcel = true;
    });

    try {
      final excel =
          Excel.createExcel();

      final sheet =
          excel['Lançamentos'];

      sheet.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Vencimento'),
        TextCellValue('Data'),
        TextCellValue('Descrição'),
        TextCellValue('Categoria'),
        TextCellValue('Valor'),
        TextCellValue('Parcela atual'),
        TextCellValue('Total parcelas'),
        TextCellValue('Tipo'),
        TextCellValue('Observações'),
      ]);

      for (final fatura in faturas) {
        for (final item
            in fatura
                .resultado
                .lancamentos) {
          sheet.appendRow([
            TextCellValue(
              fatura.arquivo,
            ),
            TextCellValue(
              fatura
                  .resultado
                  .vencimento,
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

      final conf =
          excel['Conferência'];

      conf.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Total fatura'),
        TextCellValue('Subtotal cartão'),
        TextCellValue('Soma compras'),
        TextCellValue('Diferença cartão'),
        TextCellValue('Internacional'),
        TextCellValue('Produtos/serviços'),
        TextCellValue('Lançamentos atuais'),
        TextCellValue('Encargos'),
        TextCellValue('Saldo financiado'),
        TextCellValue('Soma lançamentos'),
        TextCellValue('Diferença final'),
        TextCellValue('Compras'),
        TextCellValue('Parceladas'),
        TextCellValue('Fonte'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r =
            fatura.resultado;

        conf.appendRow([
          TextCellValue(
            fatura.arquivo,
          ),
          DoubleCellValue(
            r.totalFatura ?? 0,
          ),
          DoubleCellValue(
            r.totalCartaoInformado ??
                0,
          ),
          DoubleCellValue(
            r.somaCompras,
          ),
          DoubleCellValue(
            r.diferencaCartao ?? 0,
          ),
          DoubleCellValue(
            r.totalInternacionalInformado ??
                0,
          ),
          DoubleCellValue(
            r.totalServicosInformado ??
                0,
          ),
          DoubleCellValue(
            r.totalLancamentosAtuaisInformado ??
                0,
          ),
          DoubleCellValue(
            r.totalEncargosInformado ??
                0,
          ),
          DoubleCellValue(
            r.saldoFinanciadoInformado ??
                0,
          ),
          DoubleCellValue(
            r.soma,
          ),
          DoubleCellValue(
            r.diferenca ?? 0,
          ),
          IntCellValue(
            r.compras.length,
          ),
          IntCellValue(
            r.quantidadeParceladas,
          ),
          TextCellValue(
            fatura.parserEscolhido,
          ),
          TextCellValue(
            r.status,
          ),
        ]);
      }

      if (excel.tables
          .containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes =
          excel.encode();

      if (bytes == null) {
        throw Exception(
          'Falha ao gerar Excel.',
        );
      }

      final pasta =
          await getTemporaryDirectory();

      final arq = File(
        '${pasta.path}/'
        'Faturas_Itau_conferidas.xlsx',
      );

      await arq.writeAsBytes(
        bytes,
      );

      await Share.shareXFiles(
        [
          XFile(
            arq.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar Excel: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          gerandoExcel = false;
        });
      }
    }
  }

  // ==========================================================
  // FORMATAÇÃO
  // ==========================================================

  String dinheiro(double valor) {
    final negativo =
        valor < 0;

    final partes =
        valor
            .abs()
            .toStringAsFixed(2)
            .split('.');

    final inteiro =
        partes[0];

    final b =
        StringBuffer();

    for (var i = 0;
        i < inteiro.length;
        i++) {
      final restante =
          inteiro.length - i;

      b.write(
        inteiro[i],
      );

      if (restante > 1 &&
          restante % 3 == 1) {
        b.write('.');
      }
    }

    return '${negativo ? '-' : ''}'
        'R\$ ${b.toString()},'
        '${partes[1]}';
  }

  Widget linha(
    String nome,
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
            child: Text(nome),
          ),
          const SizedBox(
            width: 10,
          ),
          Flexible(
            child: Text(
              valor,
              textAlign:
                  TextAlign.right,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
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

  // ==========================================================
  // INTERFACE
  // ==========================================================

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
            height: 15,
          ),

          if (processando)
            const LinearProgressIndicator(),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child:
                  Text(status),
            ),
          ),

          if (faturas.isNotEmpty) ...[
            const SizedBox(
              height: 15,
            ),

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  children: [
                    linha(
                      'Faturas processadas',
                      '${faturas.length}',
                    ),
                    linha(
                      'Conciliadas',
                      '$quantidadeConciliadas',
                    ),
                    linha(
                      'Incompletas',
                      '$quantidadeIncompletas',
                    ),
                    linha(
                      'Divergentes',
                      '$quantidadeDivergentes',
                    ),
                    linha(
                      'Falhas',
                      '$quantidadeFalhas',
                    ),
                    const Divider(),
                    linha(
                      'Total das faturas',
                      dinheiro(
                        valorTotalFaturas,
                      ),
                    ),
                    linha(
                      'Soma dos lançamentos',
                      dinheiro(
                        somaTotalLancamentos,
                      ),
                    ),
                    linha(
                      'Compras reconstruídas',
                      '$totalCompras',
                    ),
                    linha(
                      'Compras parceladas',
                      '$totalParceladas',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            FilledButton.icon(
              onPressed:
                  gerandoDiagnostico
                      ? null
                      : gerarDiagnosticoTotal,
              icon: const Icon(
                Icons.bug_report,
              ),
              label: Text(
                gerandoDiagnostico
                    ? 'Gerando diagnóstico total...'
                    : 'Gerar diagnóstico total',
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            FilledButton.icon(
              onPressed:
                  todasConciliadas &&
                          !gerandoExcel
                      ? gerarExcel
                      : null,
              icon: const Icon(
                Icons.table_view,
              ),
              label: Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : todasConciliadas
                        ? 'Gerar Excel consolidado'
                        : 'Excel bloqueado - existem divergências',
              ),
            ),

            const SizedBox(
              height: 25,
            ),

            const Text(
              'Conferência por fatura',
              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            ...faturas.map(
              (fatura) {
                final r =
                    fatura.resultado;

                return Card(
                  margin:
                      const EdgeInsets
                          .symmetric(
                    vertical: 8,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets
                            .all(16),
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
                                FontWeight
                                    .bold,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(
                          'Fonte: '
                          '${fatura.parserEscolhido}',
                        ),

                        if (r
                            .vencimento
                            .isNotEmpty)
                          Text(
                            'Vencimento: '
                            '${r.vencimento}',
                          ),

                        if (r
                            .cartao
                            .isNotEmpty)
                          Text(
                            'Cartão: '
                            '${r.cartao}',
                          ),

                        const SizedBox(
                          height: 12,
                        ),

                        linha(
                          'Total da fatura',
                          r.totalFatura ==
                                  null
                              ? 'Não identificado'
                              : dinheiro(
                                  r.totalFatura!,
                                ),
                        ),

                        linha(
                          'Subtotal cartão',
                          r.totalCartaoInformado ==
                                  null
                              ? 'Não identificado'
                              : dinheiro(
                                  r.totalCartaoInformado!,
                                ),
                        ),

                        linha(
                          'Soma das compras',
                          dinheiro(
                            r.somaCompras,
                          ),
                        ),

                        linha(
                          'Diferença cartão',
                          r.diferencaCartao ==
                                  null
                              ? 'Não calculada'
                              : dinheiro(
                                  r.diferencaCartao!,
                                ),
                        ),

                        if (r
                                .totalInternacionalInformado !=
                            null)
                          linha(
                            'Internacional + IOF',
                            dinheiro(
                              r.totalInternacionalInformado!,
                            ),
                          ),

                        if (r
                                .totalServicosInformado !=
                            null)
                          linha(
                            'Produtos/serviços',
                            dinheiro(
                              r.totalServicosInformado!,
                            ),
                          ),

                        if (r
                                .totalLancamentosAtuaisInformado !=
                            null)
                          linha(
                            'Lançamentos atuais',
                            dinheiro(
                              r.totalLancamentosAtuaisInformado!,
                            ),
                          ),

                        if (r
                                .totalEncargosInformado !=
                            null)
                          linha(
                            'Encargos',
                            dinheiro(
                              r.totalEncargosInformado!,
                            ),
                          ),

                        if (r
                                    .saldoFinanciadoInformado !=
                                null &&
                            r
                                    .saldoFinanciadoInformado!
                                    .abs() >
                                0.001)
                          linha(
                            'Saldo financiado',
                            dinheiro(
                              r.saldoFinanciadoInformado!,
                            ),
                          ),

                        const Divider(),

                        linha(
                          'Soma geral',
                          dinheiro(
                            r.soma,
                          ),
                        ),

                        linha(
                          'Diferença geral',
                          r.diferenca ==
                                  null
                              ? 'Não calculada'
                              : dinheiro(
                                  r.diferenca!,
                                ),
                        ),

                        linha(
                          'Compras individuais',
                          '${r.compras.length}',
                        ),

                        linha(
                          'Parceladas',
                          '${r.quantidadeParceladas}',
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        Row(
                          children: [
                            Icon(
                              r.conciliada
                                  ? Icons
                                      .check_circle
                                  : r
                                          .falhaLeitura
                                      ? Icons
                                          .error
                                      : Icons
                                          .warning_amber,
                              color:
                                  corStatus(
                                r,
                              ),
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Text(
                              r.status,
                              style:
                                  TextStyle(
                                color:
                                    corStatus(
                                  r,
                                ),
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                          ],
                        ),

                        if (r
                            .alertas
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
                              child:
                                  Text(
                                '• $alerta',
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(
                          height: 12,
                        ),

                        OutlinedButton.icon(
                          onPressed: () {
                            gerarDiagnostico(
                              fatura,
                            );
                          },
                          icon: const Icon(
                            Icons.description,
                          ),
                          label:
                              const Text(
                            'Gerar diagnóstico desta fatura',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
