package TAEB::AI::Magus::Goal::KillShopkeepers;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'GetCrowned' }

1;

