class Transaction {
  final String txHash;
  final String from;
  final String to;
  final String amount;
  final String tokenSymbol;
  final String direction;
  final String status;
  final String timestamp;
  final String blockchainName;
  final double? price;
  final String? temporaryId;

  Transaction({
    required this.txHash,
    required this.from,
    required this.to,
    required this.amount,
    required this.tokenSymbol,
    required this.direction,
    required this.status,
    required this.timestamp,
    required this.blockchainName,
    this.price,
    this.temporaryId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      txHash: json['txHash'] ?? '',
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      amount: json['amount'] ?? '0',
      tokenSymbol: json['tokenSymbol'] ?? '',
      direction: json['direction'] ?? 'outbound',
      status: json['status'] ?? 'completed',
      timestamp: json['timestamp'] ?? '',
      blockchainName: json['blockchainName'] ?? '',
      price: json['price'] != null ? double.tryParse(json['price'].toString()) : null,
      temporaryId: json['temporaryId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txHash': txHash,
      'from': from,
      'to': to,
      'amount': amount,
      'tokenSymbol': tokenSymbol,
      'direction': direction,
      'status': status,
      'timestamp': timestamp,
      'blockchainName': blockchainName,
      'price': price,
      'temporaryId': temporaryId,
    };
  }
}

class TransactionsRequest {
  final String UserID;

  TransactionsRequest({required this.UserID});

  Map<String, dynamic> toJson() {
    return {
      'UserID': UserID,
    };
  }
}

class TransactionsResponse {
  final String status;
  final List<Transaction> transactions;

  TransactionsResponse({
    required this.status,
    required this.transactions,
  });

  factory TransactionsResponse.fromJson(Map<String, dynamic> json) {
    return TransactionsResponse(
      status: json['status'] ?? '',
      transactions: (json['transactions'] as List<dynamic>?)
          ?.map((e) => Transaction.fromJson(e))
          .toList() ?? [],
    );
  }
} 