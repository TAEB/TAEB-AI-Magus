package TAEB::AI::Magus::Goal::GetCrowned;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'CoalignedAltar' }

1;

