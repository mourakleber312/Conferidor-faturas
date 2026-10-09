part of '../main.dart';

class Lancamento {
  final String data;
  final String descricao;
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacoes;

  const Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    this.parcelaAtual,
    this.totalParcelas,
    this.observacoes = '',
  });

  bool get parcelada => parcelaAtual != null && totalParcelas != null;
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
  final String estrategia;
  final List<Lancamento> lancamentos;
  final List<Lancamento> compras;
  final List<String> alertas;

  const ResultadoFatura({
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
    this.estrategia = '',
    this.alertas = const [],
  });

  double get soma =>
      lancamentos.fold<double>(0, (s, e) => s + e.valor);

  double get somaCompras =>
      compras.fold<double>(0, (s, e) => s + e.valor);

  double? get diferenca =>
      totalFatura == null ? null : totalFatura! - soma;

  double? get diferencaCartao =>
      totalCartaoInformado == null
          ? null
          : totalCartaoInformado! - somaCompras;

  int get quantidadeParceladas =>
      compras.where((e) => e.parcelada).length;

  bool get comprasConciliadas =>
      totalCartaoInformado != null &&
      (ParserItau.centavos(totalCartaoInformado!) -
                  ParserItau.centavos(somaCompras))
              .abs() <=
          1;

  bool get lancamentosAtuaisConciliados {
    if (totalLancamentosAtuaisInformado == null ||
        totalCartaoInformado == null) {
      return false;
    }

    final componentes =
        ParserItau.centavos(totalCartaoInformado!) +
        ParserItau.centavos(totalInternacionalInformado ?? 0) +
        ParserItau.centavos(totalServicosInformado ?? 0);

    return (ParserItau.centavos(totalLancamentosAtuaisInformado!) -
                componentes)
            .abs() <=
        1;
  }

  bool get totalConciliado {
    if (totalFatura == null) {
      return false;
    }

    if (totalLancamentosAtuaisInformado != null) {
      final esperado =
          ParserItau.centavos(totalLancamentosAtuaisInformado!) +
          ParserItau.centavos(totalEncargosInformado ?? 0);

      return (ParserItau.centavos(totalFatura!) - esperado).abs() <= 1;
    }

    if (totalCartaoInformado == null) {
      return false;
    }

    final esperado =
        ParserItau.centavos(totalCartaoInformado!) +
        ParserItau.centavos(totalInternacionalInformado ?? 0) +
        ParserItau.centavos(totalServicosInformado ?? 0) +
        ParserItau.centavos(totalEncargosInformado ?? 0);

    return (ParserItau.centavos(totalFatura!) - esperado).abs() <= 1;
  }

  bool get conciliada =>
      comprasConciliadas &&
      totalConciliado &&
      (totalLancamentosAtuaisInformado == null ||
          lancamentosAtuaisConciliados);

  bool get falhaLeitura =>
      totalFatura == null &&
      totalCartaoInformado == null;

  String get status {
    if (falhaLeitura) {
      return 'FALHA DE LEITURA';
    }

    if (conciliada) {
      return 'CONCILIADA';
    }

    if (totalConciliado) {
      return 'INCOMPLETA';
    }

    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;
  final String textoLayout;
  final String textoLayoutPaginas;
  final String textoGeometrico;
  final String textoBruto;

  const FaturaProcessada({
    required this.arquivo,
    required this.resultado,
    required this.textoLayout,
    required this.textoLayoutPaginas,
    required this.textoGeometrico,
    required this.textoBruto,
  });
}

class ValorEncontrado {
  final int inicio;
  final int fim;
  final double valor;

  const ValorEncontrado(
    this.inicio,
    this.fim,
    this.valor,
  );
}

class Candidato {
  final String nome;
  final List<Lancamento> compras;

  const Candidato(
    this.nome,
    this.compras,
  );

  int get somaCentavos {
    return compras.fold<int>(
      0,
      (s, e) =>
          s + ParserItau.centavos(e.valor),
    );
  }
}

