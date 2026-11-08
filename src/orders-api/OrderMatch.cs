namespace OrdersApi;

public static class OrderMath
{

    // Price x quantity, minus a percentage discount, rounded to cents

    public static decimal Total(decimal unitPrice, int quantity, decimal discountPercent = 0)
    {
        if (quantity < 1)
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be at least 1.");

        var subtotal = unitPrice * quantity;
        return Math.Round(subtotal * (1 - discountPercent / 100m), 2);
    }
}