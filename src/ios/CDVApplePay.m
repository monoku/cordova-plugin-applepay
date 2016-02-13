#import "CDVApplePay.h"
#import "Stripe.h"
#import "STPTestPaymentAuthorizationViewController.h"
#import <PassKit/PassKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Stripe.h"
#import <AddressBook/AddressBook.h>

@implementation CDVApplePay

- (CDVPlugin*)initWithWebView:(UIWebView*)theWebView
{
    [Stripe setDefaultPublishableKey:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"StripePublishableKey"]];
    self = (CDVApplePay*)[super initWithWebView:(UIWebView*)theWebView];

    return self;
}

- (void)dealloc
{

}

- (void)onReset
{

}

- (void)setMerchantId:(CDVInvokedUrlCommand*)command
{
    merchantId = [command.arguments objectAtIndex:0];
    NSLog(@"ApplePay set merchant id to %@", merchantId);
}

- (void)getAllowsApplePay:(CDVInvokedUrlCommand*)command
{
    if (merchantId == nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"Please call setMerchantId() with your Apple-given merchant ID."];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    PKPaymentRequest *request = [Stripe
                                 paymentRequestWithMerchantIdentifier:merchantId];

    // Configure a dummy request
    NSString *label = @"Premium Llama Food";
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:@"10.00"];
    request.paymentSummaryItems = @[
                                    [PKPaymentSummaryItem summaryItemWithLabel:label
                                                                        amount:amount]
                                    ];

    if ([Stripe canSubmitPaymentRequest:request]) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"user has apple pay"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    } else {
#if DEBUG
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"in debug mode, simulating apple pay"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
#else
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"user does not have apple pay"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
#endif
    }
}

- (void)getStripeToken:(CDVInvokedUrlCommand*)command
{

    if (merchantId == nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"Please call setMerchantId() with your Apple-given merchant ID."];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    PKPaymentRequest *request = [Stripe
                                 paymentRequestWithMerchantIdentifier:merchantId];

    NSLog(@"Total %@", [command.arguments objectAtIndex:0]);
    NSLog(@"Subtotal %@", [command.arguments objectAtIndex:3]);
    NSLog(@"Delivery %@", [command.arguments objectAtIndex:4]);
    NSLog(@"Taxes %@", [command.arguments objectAtIndex:5]);

    // subTotal
    NSString *subtotalLabel = @"Subtotal";
    NSDecimalNumber *subtotalAmount = [NSDecimalNumber decimalNumberWithString:[command.arguments objectAtIndex:3]];
    // delivery
    NSString *deliveryLabel = @"Delivery";
    NSDecimalNumber *deliveryAmount = [NSDecimalNumber decimalNumberWithString:[command.arguments objectAtIndex:4]];
    // taxes
    NSString *taxesLabel = @"Taxes";
    NSDecimalNumber *taxesAmount = [NSDecimalNumber decimalNumberWithString:[command.arguments objectAtIndex:5]];
    // Total
    NSString *totalLabel = [command.arguments objectAtIndex:1];
    NSDecimalNumber *totalAmount = [NSDecimalNumber decimalNumberWithString:[command.arguments objectAtIndex:0]];


    request.paymentSummaryItems = @[
                                    [PKPaymentSummaryItem summaryItemWithLabel:subtotalLabel
                                                                        amount:subtotalAmount],
                                    [PKPaymentSummaryItem summaryItemWithLabel:deliveryLabel
                                                                        amount:deliveryAmount],
                                    [PKPaymentSummaryItem summaryItemWithLabel:taxesLabel
                                                                        amount:taxesAmount],
                                    [PKPaymentSummaryItem summaryItemWithLabel:totalLabel
                                                                        amount:totalAmount]
                                    ];

    NSString *cur = [command.arguments objectAtIndex:2];
    request.currencyCode = cur;

    request.requiredShippingAddressFields = PKAddressFieldEmail;
    request.requiredShippingAddressFields = PKAddressFieldEmail | PKAddressFieldPostalAddress;
    //    request.requiredBillingAddressFields = PKAddressFieldPostalAddress;

    callbackId = command.callbackId;


#if DEBUG
    STPTestPaymentAuthorizationViewController *paymentController;
    paymentController = [[STPTestPaymentAuthorizationViewController alloc]
                         initWithPaymentRequest:request];
    paymentController.delegate = self;
    [self.viewController presentViewController:paymentController animated:YES completion:nil];
#else
    if ([Stripe canSubmitPaymentRequest:request]) {
        PKPaymentAuthorizationViewController *paymentController;
        paymentController = [[PKPaymentAuthorizationViewController alloc]
                             initWithPaymentRequest:request];
        paymentController.delegate = self;
        [self.viewController presentViewController:paymentController animated:YES completion:nil];
    } else {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"You dont have access to ApplePay"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
#endif
}

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                       didAuthorizePayment:(PKPayment *)payment
                                completion:(void (^)(PKPaymentAuthorizationStatus))completion {


    //    NSError *error;

    ABMultiValueRef addressMultiValue = ABRecordCopyValue(payment.shippingAddress, kABPersonAddressProperty);
    ABMultiValueRef emailMultiValue = ABRecordCopyValue(payment.shippingAddress, kABPersonEmailProperty);
    NSDictionary *addressDictionary = (__bridge_transfer NSDictionary *) ABMultiValueCopyValueAtIndex(addressMultiValue, 0);
    NSString *email = (__bridge_transfer NSString *) ABMultiValueCopyValueAtIndex(emailMultiValue, 0);
    //    NSData *json = [NSJSONSerialization dataWithJSONObject:addressDictionary options:NSJSONWritingPrettyPrinted error: &error];
    NSLog(@"%@",addressDictionary);
    NSLog(@"%@",email);

    if (!email) {
        email = @"";
    }

    void(^tokenBlock)(STPToken *token, NSError *error) = ^void(STPToken *token, NSError *error) {
        if (error) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"couldn't get a stripe token from STPAPIClient"];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
            return;
        }
        else {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{ @"address": addressDictionary,
                                                                                                                   @"token": token.tokenId,
                                                                                                                   @"email": email
                                                                                                                   }];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        }
        [self.viewController dismissViewControllerAnimated:YES completion:nil];
    };


#if DEBUG
    STPCard *card = [STPCard new];
    card.number = @"4111111111111111";
    card.expMonth = 12;
    card.expYear = 2020;
    card.cvc = @"123";
    [[STPAPIClient sharedClient] createTokenWithCard:card completion:tokenBlock];
#else
    [[STPAPIClient sharedClient] createTokenWithPayment:payment
                                             completion:tokenBlock];
#endif
}

- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"user cancelled apple pay"];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

@end
