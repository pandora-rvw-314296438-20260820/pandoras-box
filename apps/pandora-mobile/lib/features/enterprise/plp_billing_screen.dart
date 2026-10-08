import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/pandora_config.dart';
import '../../app/pandora_dependencies.dart';
import '../../core/security/pandora_auth.dart';

class PlpBillingScreen extends StatefulWidget {
  const PlpBillingScreen({super.key, required this.organizationId, required this.onOpenNavigation});
  final String? organizationId;
  final VoidCallback onOpenNavigation;
  @override State<PlpBillingScreen> createState() => _PlpBillingScreenState();
}

class _PlpBillingScreenState extends State<PlpBillingScreen> {
  static const _canvas=Color(0xFFFAF8F3), _ink=Color(0xFF171512), _muted=Color(0xFF746F67), _accent=Color(0xFF82764F);
  static const _plans=<PlpBillingPlan>[
    PlpBillingPlan(code:'launch',name:'Launch',price:49,requests:'1,000 requests / month'),
    PlpBillingPlan(code:'professional',name:'Professional',price:149,requests:'5,000 requests / month'),
  ];
  Map<String,dynamic>? _subscription;
  Map<String,dynamic>? _checkout;
  bool _loading=true,_busy=false;
  String? _message;

  @override void initState(){super.initState();_load();}

  Future<Map<String,dynamic>> _request(String method,String route,{Map<String,dynamic>? body}) async {
    final session=Supabase.instance.client.auth.currentSession;
    final organizationId=widget.organizationId?.trim();
    if(session==null) throw const PlpBillingException('SIGN_IN_REQUIRED');
    if(organizationId==null||organizationId.isEmpty) throw const PlpBillingException('ORGANIZATION_REQUIRED');
    final request=http.Request(method,Uri.parse(PandoraConfig.ownerApiBaseUrl+route));
    request.headers['Accept']='application/json';
    request.headers['Authorization']='Bearer '+session.accessToken;
    request.headers['X-Organization-Id']=organizationId;
    if(body!=null){request.headers['Content-Type']='application/json';request.body=jsonEncode(body);}
    final client=http.Client();
    try{
      final response=await client.send(request).timeout(const Duration(seconds:25));
      final raw=await response.stream.bytesToString();
      final decoded=raw.trim().isEmpty?<String,dynamic>{}:jsonDecode(raw);
      final payload=decoded is Map?decoded.map((key,value)=>MapEntry(key.toString(),value)):<String,dynamic>{};
      if(response.statusCode<200||response.statusCode>=300)throw PlpBillingException(payload['code']?.toString()??'HTTP_'+response.statusCode.toString(),payload['plainMessage']?.toString());
      return payload;
    }finally{client.close();}
  }

  Future<Map<String,dynamic>> _mutation(String route,Map<String,dynamic> body) async {
    try{return await _request('POST',route,body:body);}
    on PlpBillingException catch(error){
      if(error.code!='AAL2_REQUIRED'&&error.code!='STEP_UP_REQUIRED')rethrow;
      final auth=PandoraDependencies.of(context).auth;
      if(auth is! ExtraIdentityVerificationSource)rethrow;
      final factors=await auth.verifiedExtraIdentityFactors();
      if(!mounted||factors.isEmpty)rethrow;
      final input=await _showVerification(factors);
      if(input==null)rethrow;
      await auth.verifyExtraIdentity(factorId:input.factorId,code:input.code);
      return _request('POST',route,body:body);
    }
  }

  Future<PlpBillingMfaInput?> _showVerification(List<ExtraIdentityFactor> factors) {
    final controller=TextEditingController();
    return showDialog<PlpBillingMfaInput>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:const Text('Verify identity'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Billing changes require your verified authenticator.'),
          const SizedBox(height:12),
          Text(factors.first.label,style:const TextStyle(fontWeight:FontWeight.w600)),
          const SizedBox(height:12),
          TextField(controller:controller,autofocus:true,keyboardType:TextInputType.number,maxLength:8,decoration:const InputDecoration(labelText:'Verification code',counterText:'')),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.of(dialogContext).pop(PlpBillingMfaInput(factors.first.id,controller.text.trim())),child:const Text('Verify')),
        ],
      ),
    );
  }

  Future<void> _load() async {
    if(!mounted)return;
    setState(()=>_loading=true);
    try{
      final payload=await _request('GET','/billing/paypal/status');
      if(!mounted)return;
      setState((){_subscription=_map(payload['subscription']);_checkout=_map(payload['checkout']);_loading=false;});
    }catch(error){
      if(mounted)setState((){_loading=false;_message=_friendly(error);});
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if(_busy)return;
    setState(()=>_busy=true);
    try{await action();await _load();}catch(error){if(mounted)setState(()=>_message=_friendly(error));}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  String _key(String prefix)=>prefix+'-'+DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _start(PlpBillingPlan plan) async {
    await _run(()async{
      final result=await _mutation('/billing/paypal/checkout',{
        'planCode':plan.code,'idempotencyKey':_key('checkout-'+plan.code),
        'returnUrl':'https://pandoras-box-system.vercel.app/','cancelUrl':'https://pandoras-box-system.vercel.app/',
      });
      await _openApproval(result['approvalUrl']);
      if(mounted)setState(()=>_message='PayPal approval opened. Return to Pandora and refresh Billing.');
    });
  }

  Future<void> _change(PlpBillingPlan plan) async {
    await _run(()async{
      final result=await _mutation('/billing/paypal/change-plan',{
        'planCode':plan.code,'idempotencyKey':_key('change-'+plan.code),
      });
      final approval=result['approvalUrl']?.toString();
      if(approval!=null&&approval.isNotEmpty)await _openApproval(approval);
      if(mounted)setState(()=>_message='Plan change submitted. PayPal approval is required.');
    });
  }

  Future<void> _cancel() async {
    final confirmed=await showDialog<bool>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:const Text('Cancel subscription?'),
        content:const Text('Pandora will send the cancellation request to PayPal.'),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(false),child:const Text('Keep subscription')),
          FilledButton(onPressed:()=>Navigator.of(dialogContext).pop(true),child:const Text('Cancel subscription')),
        ],
      ),
    );
    if(confirmed!=true)return;
    await _run(()async{
      await _mutation('/billing/paypal/cancel',{'reason':'Cancelled by Pandora owner'});
      if(mounted)setState(()=>_message='Cancellation requested. Refresh after PayPal confirms it.');
    });
  }

  Future<void> _reconcile() async {
    await _run(()async{
      await _mutation('/billing/paypal/reconcile',const <String,dynamic>{});
      if(mounted)setState(()=>_message='Billing state reconciled with PayPal.');
    });
  }

  Future<void> _openApproval(Object? value) async {
    final uri=Uri.tryParse(value?.toString()??'');
    if(uri==null||uri.scheme!='https')throw const PlpBillingException('APPROVAL_URL_INVALID');
    if(!await launchUrl(uri,mode:LaunchMode.externalApplication))throw const PlpBillingException('APPROVAL_OPEN_FAILED');
  }

  String _friendly(Object error) {
    if(error is! PlpBillingException)return 'Pandora could not complete the billing request.';
    return switch(error.code){
      'SIGN_IN_REQUIRED'=>'Sign in again to manage billing.',
      'ORGANIZATION_REQUIRED'=>'The PLP organization could not be verified.',
      'AAL2_REQUIRED'||'STEP_UP_REQUIRED'=>'Verify your identity before changing billing.',
      'PAYPAL_AUTH_FAILED'=>'PayPal is configured but its live credentials need attention.',
      'PAYPAL_NOT_CONFIGURED'=>'PayPal credentials are not configured yet.',
      'ACTIVE_SUBSCRIPTION_EXISTS'=>'An active subscription already exists for this workspace.',
      'SUBSCRIPTION_NOT_FOUND'=>'No active Pandora subscription was found.',
      'PAYPAL_PLAN_SAME'=>'That is already the active plan.',
      _=>error.message??'Pandora could not complete the billing request.',
    };
  }

  @override Widget build(BuildContext context) {
    final state=_subscription?['state']?.toString().toLowerCase();
    final fee=int.tryParse(_subscription?['monthly_fee_micros']?.toString()??'');
    final currentCode=fee==49000000?'launch':fee==149000000?'professional':_checkout?['plan_code']?.toString()??'';
    final hasSubscription=_subscription!=null&&state!=null&&state!='cancelled';
    final status=state=='active'?'Active':state=='past_due'?'Payment needs attention':state=='suspended'?'Suspended':state=='cancelled'?'Cancelled':'No active subscription';
    return Scaffold(
      backgroundColor:_canvas,
      body:SafeArea(child:RefreshIndicator(onRefresh:_load,child:ListView(
        padding:const EdgeInsets.fromLTRB(20,18,20,120),
        children:[
          Row(children:[
            IconButton(onPressed:widget.onOpenNavigation,icon:const Icon(Icons.menu_rounded,color:_ink)),
            const Expanded(child:Text('BILLING',style:TextStyle(color:_ink,fontFamily:'serif',fontSize:16,fontWeight:FontWeight.w400,letterSpacing:2.6))),
            IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh_rounded,color:_ink)),
          ]),
          const SizedBox(height:24),
          Text('Pandora subscription',style:Theme.of(context).textTheme.headlineSmall?.copyWith(color:_ink,fontWeight:FontWeight.w700)),
          const SizedBox(height:8),
          const Text('Manage your Pandora plan without leaving the PLP workspace.',style:TextStyle(color:_muted,height:1.45)),
          const SizedBox(height:20),
          Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFFF0ECE4),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE0D8CC))),child:Row(children:[
            const Icon(Icons.credit_card_rounded,color:_accent,size:26),const SizedBox(width:14),Expanded(child:Text(status,style:const TextStyle(color:_ink,fontSize:17,fontWeight:FontWeight.w700))),
            IconButton(onPressed:_busy?null:_reconcile,icon:const Icon(Icons.sync_rounded,color:_ink)),
          ])),
          if(_message!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_message!,style:const TextStyle(color:_muted,height:1.4))),
          const SizedBox(height:22),
          if(_loading)const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()))
          else ...[
            const Text('Plans',style:TextStyle(color:_ink,fontSize:20,fontWeight:FontWeight.w700)),
            const SizedBox(height:12),
            for(final plan in _plans)...[_planCard(plan,currentCode,hasSubscription),const SizedBox(height:12)],
            if(hasSubscription)Row(children:[
              Expanded(child:OutlinedButton.icon(onPressed:_busy?null:_reconcile,icon:const Icon(Icons.sync_rounded),label:const Text('Reconcile'))),
              const SizedBox(width:10),
              Expanded(child:OutlinedButton.icon(onPressed:_busy?null:_cancel,icon:const Icon(Icons.close_rounded),label:const Text('Cancel'))),
            ]),
          ],
        ],
      ))),
    );
  }

  Widget _planCard(PlpBillingPlan plan,String currentCode,bool hasSubscription) {
    final active=currentCode==plan.code;
    return Container(
      padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:active?_accent:const Color(0xFFE4DED4),width:active?1.5:1)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Text(plan.name,style:const TextStyle(color:_ink,fontSize:20,fontWeight:FontWeight.w700))),if(active)const Text('CURRENT',style:TextStyle(color:_accent,fontSize:10,fontWeight:FontWeight.w800,letterSpacing:1.1))]),
        const SizedBox(height:6),
        Text('\$'+plan.price.toString()+' / month',style:const TextStyle(color:_ink,fontSize:28,fontWeight:FontWeight.w800)),
        const SizedBox(height:4),
        Text(plan.requests,style:const TextStyle(color:_muted)),
        const SizedBox(height:16),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:_busy||active?null:()=>hasSubscription?_change(plan):_start(plan),child:Text(hasSubscription?'Change to '+plan.name:'Start '+plan.name))),
      ]),
    );
  }
}

class PlpBillingPlan {
  const PlpBillingPlan({required this.code,required this.name,required this.price,required this.requests});
  final String code; final String name; final int price; final String requests;
}
class PlpBillingMfaInput {
  const PlpBillingMfaInput(this.factorId,this.code);
  final String factorId; final String code;
}
class PlpBillingException implements Exception {
  const PlpBillingException(this.code,[this.message]);
  final String code; final String? message;
}
Map<String,dynamic> _map(Object? value){
  if(value is Map<String,dynamic>)return value;
  if(value is Map)return value.map((key,item)=>MapEntry(key.toString(),item));
  return <String,dynamic>{};
}
