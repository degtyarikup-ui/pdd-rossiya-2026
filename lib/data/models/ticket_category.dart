enum TicketCategory {
  ab,
  cd;

  static TicketCategory parse(String? raw) {
    switch (raw) {
      case 'cd':
        return TicketCategory.cd;
      default:
        return TicketCategory.ab;
    }
  }
}
