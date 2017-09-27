#!/usr/bin/env python
###############################################################
# < next few lines under version control, D O  N O T  E D I T >
# $Date$
# $Revision$
# $Author$
# $Id$
###############################################################


'''
This script expects the following directory structure:

ICSDIR/
    - CDATE/ (YYYYMMDDHH)
        - gdas.tHHz.abias
        - gdas.tHHz.abias_pc
        - gdas.tHHz.abias_air
        - gdas.tHHz.radstat
        - T1534/ (JCAP_det, typically from operations)
            - gdas.tHHz.atmanl.nemsio
            - gdas.tHHz.sfcanl.nemsio
            - gdas.tHHz.nstanl.nemsio (optional)
        - T574/ (JCAP_ens, typically from operations)
            - gdas.tHHz.atmanl.memXXX.nemsio
            - gdas.tHHz.sfcanl.memXXX.nemsio
            - gdas.tHHz.nstanl.memXXX.nemsio (optional)
        - C96/ (CASE_det, CASE_ens)
            - control
                - fv3ics.log (chgres log going to C96 for control)
                - INPUT/
                    - gfs_data.nc
                    - ...
            - mem001
                - fv3ics.log (chgres log going to C96 for member 001)
                - INPUT/
                    - gfs_data.nc
                    - ...
            ...
'''


import os
import sys
import glob
import subprocess
import string
import random
import argparse


__author__ = "Rahul Mahajan"
__organization__ = "NOAA/NCEP/EMC"
__email__ = "rahul.mahajan@noaa.gov"
__version__ = '1.0.0'


def set_machine():

    if os.path.isdir('/scratch4'):
        return 'THEIA'
    elif os.path.isdir('/gpfs'):
        return 'WCOSS_C'
    else:
        raise NotImplementedError('Unknown machine')


def set_paths():

    if machine in ['THEIA']:
        base_gsm = "/scratch4/NCEPDEV/global/save/glopara/svn/fv3gfs/trunk/global_shared.v15.0.0"
        stmp = "/scratch4/NCEPDEV/stmp4/%s" % os.environ['USER']
    elif machine in ['WCOSS_C']:
        base_gsm = "/gpfs/hps3/emc/global/noscrub/emc.glopara/svn/fv3gfs/trunk/global_shared.v15.0.0"
        stmp = "/gpfs/hps3/stmp/%s" % os.environ['USER']

    return base_gsm, stmp


def get_accountinfo():

    if machine in ['THEIA']:
        queue, account = 'batch', 'fv3-cpu'
    elif machine in ['WCOSS_C']:
        queue, account = 'dev', 'FV3GFS-T2O'

    return queue, account


def get_jobcard():

    queue, account = get_accountinfo()

    mdict = {'queue':queue, 'account': account, 'icsdir':icsdir, 'date':date, 'pwd':os.environ['PWD'], 'nthreads':nthreads}

    if machine in ['WCOSS_C']:

        strings = '''
#BSUB -J fv3ics_<TEMPLATE_MEMBER>
#BSUB -P {account}
#BSUB -q {queue}
#BSUB -W 0:30
#BSUB -M 3072
#BSUB -extsched 'CRAYLINUX[]' -R '1*{{select[craylinux && !vnode]}} + 24*{{select[craylinux && vnode]span[ptile=24] cu[type=cabinet]}}'
#BSUB -e {icsdir}/{date}/<TEMPLATE_CASE>/<TEMPLATE_MEMBER>/fv3ics.log
#BSUB -o {icsdir}/{date}/<TEMPLATE_CASE>/<TEMPLATE_MEMBER>/fv3ics.log
#BSUB -cwd {pwd}
'''.format(**mdict)

    elif machine in ['THEIA']:

        strings = '''
#PBS -N fv3ics_<TEMPLATE_MEMBER>
#PBS -A {account}
#PBS -q {queue}
#PBS -l walltime=00:30:00
#PBS -l nodes=1:ppn={nthreads}
#PBS -o {icsdir}/{date}/<TEMPLATE_CASE>/<TEMPLATE_MEMBER>/fv3ics.log
#PBS -j oe
'''.format(**mdict)

    return strings


def get_jobtemplate():

    strings = '''#!/bin/sh'''

    strings += get_jobcard()

    mdict = {'machine':machine, 'base_gsm':base_gsm, 'stmp':stmp, 'date':date, 'icsdir':icsdir, 'nthreads':nthreads
    }
    strings += '''
set -x
export machine={machine}

export BASE_GSM={base_gsm}
export STMP={stmp}

export CDATE={date}
export CASE=<TEMPLATE_CASE>
export INIDIR={icsdir}/$CDATE/<TEMPLATE_JCAP>
export OUTDIR={icsdir}/$CDATE/$CASE/<TEMPLATE_MEMBER>/INPUT
export DATA=$STMP/RUNDIRS/tmpdir.fv3ics/$CDATE/$CASE/<TEMPLATE_MEMBER>

export OMP_NUM_THREADS_CH={nthreads}
'''.format(**mdict)

    strings += '''
export ATMANL=$INIDIR/<TEMPLATE_ATM>
export SFCANL=$INIDIR/<TEMPLATE_SFC>
'''
    if nsst:
        strings += '''export NSTANL=$INIDIR/<TEMPLATE_NST>
'''

    if machine in ['WCOSS_C']:
        strings += '''
export APRUNC="aprun -j 1 -n 1 -N 1 -d $OMP_NUM_THREADS_CH -cc depth"
'''

    strings += '''
[[ -d $DATA ]] && rm -rf $DATA
[[ -d $OUTDIR ]] && rm -rf $OUTDIR
mkdir -p $OUTDIR

$BASE_GSM/ush/global_chgres_driver.sh
status=$?
exit $status
'''

    return strings


def get_jobscript(member, files, jcap, case, strings):

    strings = strings.replace('<TEMPLATE_MEMBER>', member)
    strings = strings.replace('<TEMPLATE_JCAP>', jcap)
    strings = strings.replace('<TEMPLATE_CASE>', case)

    strings = strings.replace('<TEMPLATE_ATM>', files['atmanl'])
    strings = strings.replace('<TEMPLATE_SFC>', files['sfcanl'])
    if nsst:
        strings = strings.replace('<TEMPLATE_NST>', files['nstanl'])

    return strings


def get_submitcmd():

    if machine in ['THEIA']:
        cmd = 'qsub'
    elif machine in ['WCOSS_C']:
        cmd = 'bsub <'

    return cmd


def submit_jobs(jobs, cleanup=True):

    def _random_id(length=8):
        return ''.join(random.sample(string.ascii_letters + string.digits, length))

    submit_cmd = get_submitcmd()

    for job in jobs:

        script = 'submit_%s.sh' % _random_id()
        open(script, 'wb').write(job)

        cmd = '%s %s' % (submit_cmd, script)
        try:
            subprocess.check_call(cmd, stderr=subprocess.STDOUT, shell=True)
        except subprocess.CalledProcessError as e:
            print e.output
        finally:
            if cleanup:
                os.remove(script)

    return


def main():

    global machine, base_gsm, stmp, nthreads
    global date, icsdir
    global nsst
    global CASE_det, CASE_ens, JCAP_det, JCAP_ens

    description = '''Convert GFS files into FV3 files'''

    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--date', help='date of initial conditions to convert from GFS to FV3', type=str, metavar='YYYYMMDDHH', required=True)
    parser.add_argument('--icsdir', help='full path to initial conditions directory', type=str, required=True)
    parser.add_argument('--cdump', help='cycle', type=str, required=False, default='gdas')
    parser.add_argument('--CASE_det', help='desired resolution of the FV3 deterministic initial conditions', type=int, required=False, default=None)
    parser.add_argument('--CASE_ens', help='desired resolution of the FV3 ensemble initial conditions', type=int, required=False, default=None)
    parser.add_argument('--JCAP_det', help='resolution of the deterministic GFS initial conditions', type=int, required=False, default=1534)
    parser.add_argument('--JCAP_ens', help='resolution of the ensemble GFS initial conditions', type=int, required=False, default=574)
    parser.add_argument('--nthreads', help='how many threads to use', type=int, required=False, default=24)

    input_args = parser.parse_args()

    if input_args.CASE_det is None and input_args.CASE_ens is None:
        print 'CASE_det and CASE_ens both cannot be None'
        print 'nothing to do, EXIT!'
        print '\n'
        sys.exit(1)

    date = input_args.date
    icsdir = input_args.icsdir
    CASE_det = input_args.CASE_det
    CASE_ens = input_args.CASE_ens
    JCAP_det = input_args.JCAP_det
    JCAP_ens = input_args.JCAP_ens
    nthreads = input_args.nthreads
    cdump = input_args.cdump

    PDY = date[:8]
    cyc = date[8:]

    prefix = '%s.t%sz' % (cdump, cyc)
    suffix = 'nemsio'

    chgres_det = False if CASE_det is None else True
    chgres_ens = False if CASE_ens is None else True

    machine = set_machine()
    base_gsm, stmp = set_paths()

    nsst = True if os.path.exists('%s/%s/T%s/%s.nstanl.%s' % (icsdir, date, JCAP_det, prefix, suffix)) else False

    job_template = get_jobtemplate()

    jobs = []

    if chgres_det:

        files = {}
        files['atmanl'] = '%s.atmanl.%s' % (prefix, suffix)
        files['sfcanl'] = '%s.sfcanl.%s' % (prefix, suffix)
        files['nstanl'] = '%s.nstanl.%s' % (prefix, suffix) if nsst else None

        cmd = 'mkdir -p %s/%s/C%d/control' % (icsdir, date, CASE_det)
        os.system(cmd)
        cmd = 'rm -f %s/%s/C%d/control/fv3ics.log' % (icsdir, date, CASE_det)
        os.system(cmd)
        job_script = get_jobscript('control', files, 'T%d' % JCAP_det, 'C%d' % CASE_det, job_template)
        jobs.append(job_script)

    if chgres_ens:
        nens = len(glob.glob('%s/%s/T%s/%s.ratmanl.mem???.%s' % (icsdir, date, JCAP_ens, prefix, suffix)))

        for i in range(1, nens+1):

            files = {}
            files['atmanl'] = '%s.ratmanl.mem%03d.%s' % (prefix, i, suffix)
            files['sfcanl'] = '%s.sfcanl.mem%03d.%s' % (prefix, i, suffix)
            files['nstanl'] = '%s.nstanl.mem%03d.%s' % (prefix, i, suffix) if nsst else None

            cmd = 'mkdir -p %s/%s/C%d/mem%03d' % (icsdir, date, CASE_ens, i)
            os.system(cmd)
            cmd = 'rm -f %s/%s/C%d/mem%03d/fv3ics.log' % (icsdir, date, CASE_ens, i)
            os.system(cmd)
            job_script = get_jobscript('mem%03d' % i, files, 'T%d' % JCAP_ens, 'C%d' % CASE_ens, job_template)
            jobs.append(job_script)

    submit_jobs(jobs, cleanup=True)

if __name__ == '__main__':
    main()