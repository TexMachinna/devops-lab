namespace OrdersApi.Tests;

public class OrderMathTests
{
    [Fact]
    public void Total_MultipliesPriceByQuantity()
    {
        Assert.Equal(30m, OrderMath.Total(10m, 3));
    }

    [Fact]
    public void Total_AppliesPercentageDiscount()
    {
        Assert.Equal(180m, OrderMath.Total(100m, 2, 10m));
    }

    [Fact]
    public void Total_RejectsQuantityBelowOne()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => OrderMath.Total(10m, 0));
    }
}