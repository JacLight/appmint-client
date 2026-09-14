export interface BaseModel<T = Record<string, unknown>> {
    sk: string;
    pk: string;
    datatype: string;
    name?: string;
    data: T;
    createdate?: string;
    modifydate?: string;
}
export interface Paged<T> {
    data: BaseModel<T>[];
    total: number;
    page: number;
    pageSize: number;
    hasNext: boolean;
    [k: string]: unknown;
}
export interface Product {
    sku: string;
    name: string;
    title?: string;
    price?: number;
    images?: Array<{
        url?: string;
    } | string>;
    /** What THIS customer pays. `price` is the list price — show `finalPrice`. */
    calculatedPrice?: {
        originalPrice?: number;
        finalPrice?: number;
        discount?: number;
        discountPercent?: number;
    };
    [k: string]: unknown;
}
export interface Address {
    name?: string;
    street1?: string;
    street2?: string;
    city?: string;
    state?: string;
    zip?: string;
    country?: string;
    phone?: string;
}
export interface CartItemInput {
    sku: string;
    quantity: number;
    name?: string;
    price?: number;
    unitPrice?: number;
    itemType?: 'product' | 'rental';
    [k: string]: unknown;
}
/**
 * The cart as the server priced it.
 *
 * `total` ALREADY includes tax and shipping. Render these figures; adding the
 * parts back together produces a number the customer is not charged.
 */
export interface CartSummary {
    subtotal: number;
    discount: number;
    tax: number;
    total: number;
    deposit?: number;
    productSubtotal?: number;
    productTax?: number;
    productShipping?: number;
    productTotal?: number;
    rentalSubtotal?: number;
    rentalTotal?: number;
    shippingMethod?: string;
    shippingOptions?: unknown[];
    freeShipping?: boolean;
    discounts?: Array<{
        code?: string;
        name?: string;
        amount?: number;
        type?: string;
    }>;
    /** False when a coupon was sent and rejected — the total is unchanged. */
    valid?: boolean;
    reason?: string;
    message?: string;
    cartId?: string;
    [k: string]: unknown;
}
export interface ShippingOption {
    label?: string;
    amount: number;
    currency?: string;
    service?: string;
    carrier?: string;
    freeShipping?: boolean;
    [k: string]: unknown;
}
/** `served: false` means nothing ships there — an honest refusal, not a zero rate. */
export interface ShippingOptionsResult {
    served: boolean;
    options: ShippingOption[];
    currency?: string;
    message?: string;
    problems?: Array<{
        config?: string;
        reason: string;
    }>;
}
