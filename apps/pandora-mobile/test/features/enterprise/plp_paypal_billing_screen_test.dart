import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_paypal_billing_screen.dart';

const _plans = [
  {'code':'launch','currency':'USD','monthly_fee_micros':49000000},
  {'code':'professional','currency':'USD','monthly_fee_micros':149000000},
];
final _year=DateTime.now().year;
Map<String,dynamic> _active({bool verified=true,Object? activity=const []})=> {
  'subscription': {
    'plan_code':'launch','state':'active','currency':'USD','monthly_fee_micros':49000000,
    'renews_on':'$_year-11-08',
    if(verified)'source_kind':'provider_verified',
    if(verified)'verified_at':'$_year-10-08T03:00:00Z',
  },
  'plans':_plans,
  if(activity!=null)'activity':activity,
};
class _Fake {
  _Fake(this.status);
  Map<String,dynamic> Function() status;
  final calls=<String>[];
  final opened=<Uri>[];
  final bodies=<String,Map<String,dynamic>>{};
  int launchFailures=0;
  int statusCalls=0;
  int failStatusAfter=-1;
  Object? failOn;
  Future<Map<String,dynamic>> call(String path,{String method='GET',Map<String,dynamic>? body}) async {
    final code=body?['planCode'];
    calls.add(method+' '+path+(code!=null?' '+code.toString():''));
    if(body!=null)bodies[path]=body;
    if(path.endsWith('/status')) { statusCalls++; if(failStatusAfter>0&&statusCalls>failStatusAfter)throw Exception('PAYPAL_TIMEOUT'); }
    if(failOn!=null&&path.endsWith(failOn.toString()))throw Exception('PAYPAL_TIMEOUT');
    if(path.endsWith('/checkout')||path.endsWith('/change-plan'))return {'approvalUrl':'https://www.paypal.com/approve'};
    if(path.endsWith('/cancel'))return {'cancellation':{'cancelRequested':true,'cancelled':false}};
    return status();
  }
}
Future<_Fake> _pump(WidgetTester tester,Map<String,dynamic> Function() status,{
 bool? isWeb,Uri? appBaseUri,int launchFailures=0,int failStatusAfter=-1,
}) async {
 final fake=_Fake(status)..launchFailures=launchFailures..failStatusAfter=failStatusAfter;
 await tester.pumpWidget(MaterialApp(home:PlpPaypalBillingScreen(
  organizationId:'org-1',onOpenNavigation:(){},transport:fake.call,
  isWeb:isWeb,appBaseUri:appBaseUri,
  urlLauncher:(uri) async { fake.opened.add(uri); if(fake.launchFailures>0){fake.launchFailures--;return false;} return true; },
 )));
 await tester.pumpAndSettle(); return fake;
}
Future<void> _tap(WidgetTester tester,String id) async {
 await tester.tap(find.byKey(ValueKey('plp-capability-'+id))); await tester.pumpAndSettle();
}
void main(){
 test('price micros formatting remains intact',(){
  expect(plpBillingMonthlyPrice({'monthly_fee_micros':49000000}),'USD 49 / month');
  expect(plpBillingMonthlyPrice({'monthly_fee_micros':'149000000'}),'USD 149 / month');
  expect(plpBillingMonthlyPrice({'monthly_fee_micros':149000000,'discount_micros':10500000}),'USD 138.50 / month');
  expect(plpBillingMonthlyPrice({'currency':'PHP','monthly_fee_micros':1250000000}),'PHP 1,250 / month');
  expect(plpBillingMonthlyPrice({'monthly_fee':null}),'Price unavailable');
 });
 test('return URLs stay on allowlisted origins',(){
  final u=plpPaypalReturnUrls(isWeb:true,base:Uri.parse('https://enterprise-omega-five.vercel.app/'));
  expect(u.returnUrl,'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return');
  expect(plpPaypalReturnUrls(isWeb:false,base:Uri.parse('https://enterprise-omega-five.vercel.app/')).returnUrl,
   'https://mcpmaster.vercel.app/#/enterprise/paypal-return');
  expect(plpPaypalReturnUrls(isWeb:true,base:Uri.parse('https://evil.example/')).returnUrl,
   'https://mcpmaster.vercel.app/#/enterprise/paypal-return');
 });
 testWidgets('setup, plan selection and PayPal handoff are separate steps',(tester)async{
  final f=await _pump(tester,()=>{'subscription':null,'plans':_plans});
  expect(find.text('Grow\nwhat’s next.'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('plp-billing-choose-plan')));await tester.pumpAndSettle();
  expect(find.text('Choose your plan.'),findsOneWidget);
  expect(find.text('USD 49 / month'),findsOneWidget);expect(find.text('USD 149 / month'),findsOneWidget);
  await _tap(tester,'professional');expect(f.calls.where((x)=>x.startsWith('POST')),isEmpty);
  await _tap(tester,'pay-with-paypal');expect(find.text('Continue with PayPal.'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('plp-capability-continue-to-paypal')));await tester.pumpAndSettle();
  expect(f.calls,contains('POST /billing/paypal/checkout professional'));
  expect(f.opened.single.host,'www.paypal.com');
 });
 testWidgets('active view preserves only provider-verified subscription truth',(tester)async{
  await _pump(tester,_active);expect(find.text('Subscription connected'),findsOneWidget);
  expect(find.text('Active'),findsOneWidget);expect(find.text('USD 49 / month'),findsOneWidget);
 });
 testWidgets('unverified subscription is clearly unconfirmed',(tester)async{
  await _pump(tester,()=>_active(verified:false));
  expect(find.text('Unconfirmed'),findsOneWidget);expect(find.text('Subscription status unconfirmed'),findsOneWidget);
  expect(find.text('Verified'),findsNothing);
 });
 testWidgets('change plan uses review sheet before provider write',(tester)async{
  final f=await _pump(tester,_active);await _tap(tester,'change-plan');
  expect(find.text('Change plan.'),findsOneWidget);
  expect(f.calls.where((x)=>x.contains('/change-plan')),isEmpty);
  await tester.tap(find.byKey(const ValueKey('plp-capability-switch-to-professional')));await tester.pumpAndSettle();
  expect(f.calls,contains('POST /billing/paypal/change-plan professional'));
 });
 testWidgets('cancel requires explicit confirmation and shows pending rather than false success',(tester)async{
  final f=await _pump(tester,_active);await _tap(tester,'cancel');
  expect(find.text('Cancel subscription?'),findsOneWidget);
  expect(f.calls, isNot(contains('POST /billing/paypal/cancel')));
  await tester.tap(find.byKey(const ValueKey('plp-billing-confirm-cancel')));await tester.pumpAndSettle();
  expect(find.text('Cancellation pending confirmation from PayPal.'),findsOneWidget);
 });
 testWidgets('payment history only shows actual payment rows',(tester)async{
  await _pump(tester,()=>_active(activity:[
   {'occurred_at':'$_year-10-08T03:00:00Z','amount_micros':49000000,'currency':'USD','status':'completed'},
   {'title':'Not a payment'},
  ]));
  await _tap(tester,'history');expect(find.text('Payment history.'),findsOneWidget);
  expect(find.text('USD 49'),findsOneWidget);expect(find.text('Oct 8 · Completed'),findsOneWidget);
  expect(find.text('Not a payment'),findsNothing);
 });
 testWidgets('retry reopens the same approval instead of posting a second checkout',(tester)async{
  final f=await _pump(tester,()=>{'subscription':null,'plans':_plans},launchFailures:1);
  await tester.tap(find.byKey(const ValueKey('plp-billing-choose-plan')));await tester.pumpAndSettle();
  await _tap(tester,'launch');await _tap(tester,'pay-with-paypal');
  await tester.tap(find.byKey(const ValueKey('plp-capability-continue-to-paypal')));await tester.pumpAndSettle();
  expect(find.text('We couldn’t reach PayPal.'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('plp-billing-retry')));await tester.pumpAndSettle();
  expect(f.calls.where((x)=>x.contains('/checkout')).length,1);expect(f.opened.length,2);
 });
 testWidgets('status refresh failure after browser handoff is recoverable without a second checkout',(tester)async{
  final f=await _pump(tester,()=>{'subscription':null,'plans':_plans},failStatusAfter:1);
  await tester.tap(find.byKey(const ValueKey('plp-billing-choose-plan')));await tester.pumpAndSettle();
  await _tap(tester,'launch');await _tap(tester,'pay-with-paypal');
  await tester.tap(find.byKey(const ValueKey('plp-capability-continue-to-paypal')));await tester.pumpAndSettle();
  expect(f.calls.where((x)=>x.contains('/checkout')).length,1);
  expect(find.text('PayPal opened, but billing status could not be refreshed.'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('plp-billing-refresh-status')));await tester.pumpAndSettle();
  expect(find.text('PayPal opened, but billing status could not be refreshed.'),findsNothing);
  expect(f.calls.where((x)=>x.contains('/checkout')).length,1);
 });
 testWidgets('initial transport failure shows retry without leaking internal details',(tester)async{
  await tester.pumpWidget(MaterialApp(home:PlpPaypalBillingScreen(organizationId:'org-1',onOpenNavigation: () {},
   transport:(path,{method='GET',body})async=>throw Exception('BILLING_REQUEST_FAILED'))));
  await tester.pumpAndSettle();expect(find.text('We couldn’t reach PayPal.'),findsOneWidget);
  expect(find.textContaining('BILLING_REQUEST_FAILED'),findsNothing);
  expect(find.byKey(const ValueKey('plp-billing-retry')),findsOneWidget);
 });
 testWidgets('unknown renewal date is not fabricated',(tester)async{
  await _pump(tester,(){final s=_active();(s['subscription'] as Map).remove('renews_on');return s;});
  await _tap(tester,'change-plan');
  expect(find.textContaining('current renewal date'),findsNothing);
  expect(find.textContaining('effective date will follow'),findsOneWidget);
 });

  testWidgets('an unfinished checkout keeps its PayPal approval resumable', (tester) async {
    final fake = await _pump(tester, () => {
      'subscription': null,
      'plans': _plans,
      'checkout': {
        'plan_code': 'launch',
        'status': 'approval_pending',
        'approval_url': 'https://www.paypal.com/webapps/billing/subscriptions?ba_token=EXISTING',
      },
    });
    expect(find.text('Finish in PayPal · not active yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-capability-open-paypal')), findsOneWidget);
    await _tap(tester, 'open-paypal');
    expect(fake.opened.single.queryParameters['ba_token'], 'EXISTING');
    expect(fake.calls.where((call) => call.contains('/checkout')), isEmpty);
  });

}
