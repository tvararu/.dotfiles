function led
  ledger --price-db prices.db --exchange £ --pedantic -f current.ledger $argv
end
