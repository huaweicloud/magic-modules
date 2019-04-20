# User guide

* 1、	用swagger-codege转成中间文档，分别是api.yaml ,  model.yaml 文档

```
  git clone https://github.com/zengchen1024/swagger-codegen

  git checkout magic_module

  java  -jar modules/swagger-codegen-cli/target/swagger-codegen-cli.jar generate -i /tmp/rest-services.yaml -l python -o /transfer/python > /transfer/magic-python 2>&1
```


* 2、将中间文档api.yaml  和  model.yaml文档+ 自定义配置文件 = 转换成magic-module需要的yaml格式文件
根据模板修改自定义的配置文件（详见附件），配置文件中决定了需要生成哪些api，哪些参数不显示等等。当前实例的配置文件保存在/tmp/dnat.yaml中。

``` 
vi /tmp/dnat.yaml

拷贝自己的配置文件到根据swagger生成的api、model文档所在的文件夹中
cp /tmp/dnat.yaml  /transfer/python/swagger_client/api/nat/v/


git clone https://github.com/zengchen1024/developing_util
cd  ../developing_util/utils/new_version_mm/design

python main.py
pip install pystache

执行命令生成magic-module需要的yaml文档的设计文档
python main.py /transfer/python/swagger_client/api/nat/v/ flexibleengine  dnat  /transfer/


执行命令生成magic-module需要的yaml文档
cd developing_util/utils/new_version_mm/schema
python main.py  /transfer/magic_module_compute flexibleengine  dnat  /transfer/schema/

```

* 3、将第二步骤中生成的yaml文档作为入参，用magic-module 生成terraform代码
git clone https://github.com/huaweicloud/magic-modules
gem install bundler
bundle install

生成的terraform代码在build/terraform/路径中获取
bundle exec compiler -p products/dnat/ -e terraform -o build/terraform/

**注意点:**

  将第二步生成的api.yaml和terraform.yaml文档拷贝到 magic-modules 的products中，因为工具用的相对路径，所以必须拷贝到products中
